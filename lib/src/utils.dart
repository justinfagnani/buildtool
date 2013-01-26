// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library utils;

import 'dart:async';
import 'dart:io';
import 'dart:uri';
import 'package:logging/logging.dart';

Future<String> readStreamAsString(InputStream stream) {
  var completer = new Completer();
  var sb = new StringBuffer();
  var sis = new StringInputStream(stream);
  sis
  ..onData = () {
    sb.add(sis.read());
  }
  ..onClosed = () {
    completer.complete(sb.toString());
  }
  ..onError = completer.completeError;
  return completer.future;
}

Future<String> readFileAsString(String filename) =>
    readStreamAsString(new File(filename).openInputStream());

String uriToNativePath(Uri uri) {
  if (uri.scheme != 'file') {
    throw new ArgumentError(uri);
  }
  return new Path(uri.path).toNativePath();
}

void printLogRecord(LogRecord r) {
  print("${r.loggerName} ${r.level} ${r.message}");
}

/**
 * Merges [maps] by adding the key/value pairs from each map to a new map.
 * Values in the laters maps overwrite values in the earlier maps.
 */
Map mergeMaps(List<Map> maps) {
  var result = new Map();
  for (var map in maps) {
    for (var key in map.keys) {
      result[key] = map[key];
    }
  }
  return result;
}

/**
 * A [DirectoryLister] that add the following behaviors:
 *   * Recurses the directory tree when [onDir] returns true.
 *   * After an error, doesn't call [onDir] or [onFile].
 */
class RecursiveDirectoryLister implements DirectoryLister {
  final DirectoryLister _lister;
  final FutureGroup _futureGroup;
  final Completer completer = new Completer<bool>();
  var _onDir;
  var _onFile;
  var _onError;
  var _error = false;

  RecursiveDirectoryLister(Directory dir)
    : _lister = dir.list(),
      _futureGroup = new FutureGroup() {

    _lister.onDir = _onDirHelper;
    _lister.onFile = _onFileHelper;
    _lister.onDone = _onDoneHelper;
    _lister.onError = _onErrorHelper;
  }

  RecursiveDirectoryLister.fromPath(Path path) :
      this(new Directory.fromPath(path));

  void set onDir(bool onDir(String dir)) {
    _onDir = onDir;
  }

  void _onDirHelper(String dir) {
    if (!_error && _onDir != null) {
      bool recurse = _onDir(dir);
      if (recurse) {
        var completer = new Completer();
        _futureGroup.add(completer.future);
        var childLister = new Directory(dir).list()
          ..onDir = _onDirHelper
          ..onFile = _onFile
          ..onError = _onError
          ..onDone = (s) => completer.complete(s);
      }
    }
  }

  void set onFile(void onFile(String file)) {
    _onFile = onFile;
  }

  void _onFileHelper(String file) {
    if (!_error && _onFile != null) {
      _onFile(file);
    }
  }

  void set onDone(void onDone(bool completed)) {
    _futureGroup.add(completer.future);
    _futureGroup.future.then((List values) {
      onDone(values.every((f) => f));
    });
  }

  void _onDoneHelper(bool complete) {
    if (!_error) {
      completer.complete(complete);
    }
  }

  void set onError(void onError(e)) {
    _onError = onError;
  }

  void _onErrorHelper(e) {
    _error = true;
    if (_onError != null) {
      _onError(e);
    }
  }
}


/** A future that waits until all added [Future]s complete. */
// TODO(sigmund): this should be part of the futures/core libraries.
class FutureGroup {
  const _FINISHED = -1;

  int _count = 0;
  int _pending = 0;
  Future _failedTask;
  final Completer<List> _completer = new Completer<List>();
  final List _values = [];

  /** Gets the task that failed, if any. */
  Future get failedTask => _failedTask;

  /**
   * Wait for [task] to complete.
   *
   * If this group has already been marked as completed, you'll get a
   * [FutureAlreadyCompleteException].
   *
   * If this group has a [failedTask], new tasks will be ignored, because the
   * error has already been signaled.
   */
  void add(Future task) {
    if (_failedTask != null) return;
    if (_pending == _FINISHED) throw new StateError("Future already completed");

    var index = _count;
    _count++;
    _pending++;
    _values.add(null);
    task.then((value) {
      if (_failedTask != null) return;
      _values[index] = value;
      _pending--;
      if (_pending == 0) {
        _pending = _FINISHED;
        _completer.complete(_values);
      }
    }, onError: (e) {
      if (_failedTask != null) return;
      _failedTask = task;
      _completer.completeError(e.error, e.stackTrace);
    });
  }

  Future<List> get future => _completer.future;
}
