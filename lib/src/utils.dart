// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library utils;

import 'dart:io';
import 'dart:uri';
import 'package:web_ui/src/utils.dart' show FutureGroup;
export 'package:web_ui/src/utils.dart' show FutureGroup;
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
  ..onError = completer.completeException;
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
          ..onDone = completer.complete;
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
    _futureGroup.future.then((List<Future> futures) { 
      onDone(futures.every((f) => f.value)); 
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
