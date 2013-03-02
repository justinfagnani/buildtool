// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library buildtool.util.recursive_directory_lister;

import 'dart:async';
import 'dart:io';
import 'package:buildtool/src/util/future_group.dart';

String getFullPath(String path) => new File(path).fullPathSync();

//Stream<FileSystemEntity> listDirectory(Directory dir,
//    bool recurse(Directory dir)) {
//  var controller = new StreamController<FileSystemEntity>();
//  int openStreamCount = 0;
//
//  void _list(Directory _dir, Path fullParentPath, Path localPath) {
//    var stream = _dir.list();
//    openStreamCount++;
//    StreamSubscription sub;
//    sub = stream.listen(
//        (FileSystemEntity e) {
//          var path;
//          if (e is Directory) {
//            path = new Path(e.path);
//            var expectedFullPath = fullParentPath.append(path.filename).toString();
//            var fullPath = new Path(new File.fromPath(path).fullPathSync());
//            var fixedPath = localPath.append(path.filename);
//
//            print("  onDir: $path $fixedPath $expectedFullPath $fullPath");
//
//            if (fullPath.toString() != expectedFullPath.toString()) {
//              controller.add(new Symlink(path.toString(), fixedPath.toString()));
//            } else {
//              controller.add(new Directory.fromPath(fixedPath));
//            }
//            if (recurse(e)) {
//              _list(e, fullPath, fixedPath);
//            }
//          } else if (e is File) {
//            path = new Path(e.name);
//            var expectedFullPath = fullParentPath.append(path.filename).toString();
//            var fullPath = new File.fromPath(path).fullPathSync();
//            var fixedPath = localPath.append(path.filename);
//
//            print("  onFile: $path $fixedPath $expectedFullPath $fullPath");
//
//            if (fullPath.toString() != expectedFullPath.toString()) {
//              controller.add(new Symlink(path.toString(), fixedPath.toString()));
//            } else {
//              controller.add(new File.fromPath(fixedPath));
//            }
//          }
//        },
//        onError: (AsyncError e) {
//          var error = e.error;
//          if (error is DirectoryIOException) {
//            // must be a broken symlink. error.path is local path
//            controller.add(new Symlink(null, error.path));
//          } else {
//            controller.signalError(e);
//            sub.cancel();
//          }
//        },
//        onDone: () {
//          openStreamCount--;
//          if (openStreamCount == 0) {
//            controller.close();
//          }
//        },
//        unsubscribeOnError: false);
//  }
//  var fullPath = new Path(new File(dir.path).fullPathSync());
//  _list(dir, fullPath, new Path(dir.path));
//
//  return controller.stream;
//}
//
//class Symlink extends FileSystemEntity {
//  final String target;
//  final String link;
//
//  Symlink(this.target, this.link);
//}

//
///**
// * A [DirectoryLister] that add the following behaviors:
// *   * Recurses the directory tree when [onDir] returns true.
// *   * After an error, doesn't call [onDir] or [onFile].
// *   * Symlinks are partially handled, they will be passed of [onDir] and
// *     [onFile] with directory paths that point to the location of the link,
// *     though the filename will be the name of the target.
// */
//class RecursiveDirectoryLister implements DirectoryLister {
//  final Directory _baseDir;
//  final DirectoryLister _lister;
//  final FutureGroup _futureGroup;
//  final Completer completer = new Completer<bool>();
//  final Set<String> visited = new Set<String>();
//
//  var _onDir;
//  var _onFile;
//  var _onError;
//  var _error = false;
//
//  RecursiveDirectoryLister(Directory dir)
//    : _baseDir = dir,
//      _lister = dir.list(),
//      _futureGroup = new FutureGroup() {
//
//    _futureGroup.add(completer.future);
//    var dirPath = new Path(dir.path);
//    _lister.onDir = _onDirHelper(dirPath);
//    _lister.onFile = _onFileHelper(dirPath);
//    _lister.onDone = _onDoneHelper;
//    _lister.onError = _onErrorHelper;
//  }
//
//  RecursiveDirectoryLister.fromPath(Path path) :
//      this(new Directory.fromPath(path));
//
//  void set onDir(bool onDir(String dir)) {
//    _onDir = onDir;
//  }
//
//  _onDirHelper(Path localPath) => (String dir) {
//    if (!_error && _onDir != null) {
//
//      // skip symlink cycles
//      var fullPath = getFullPath(dir);
//      if (visited.contains(fullPath)) {
//        return;
//      }
//      visited.add(fullPath);
//
//      // try to determine the local path, not resolved path, of symlinks
//      // assumes that the lister doesn't return directory paths ending in '/'
//      assert(!dir.endsWith('/'));
//      var fixedPath = localPath.append(new Path(dir).filename);
//
//      bool recurse = _onDir(fixedPath.toString());
//      if (recurse) {
//        var completer = new Completer();
//        _futureGroup.add(completer.future);
//        var childLister = new Directory(dir).list()
//          ..onDir = _onDirHelper(fixedPath)
//          ..onFile = _onFileHelper(fixedPath)
//          ..onError = _onError
//          ..onDone = (s) => completer.complete(s);
//      }
//    }
//  };
//
//  void set onFile(void onFile(String file)) {
//    _onFile = onFile;
//  }
//
//  _onFileHelper(Path localPath) => (String file) {
//    if (!_error && _onFile != null) {
//      // try to determine the local path, not resolved path, of symlinks
//      assert(!file.endsWith('/'));
//      var fixedPath = localPath.append(new Path(file).filename);
//
//      _onFile(fixedPath.toString());
//    }
//  };
//
//  void set onDone(void onDone(bool completed)) {
//    _futureGroup.future.then((List values) {
//      onDone(values.every((f) => f));
//    });
//  }
//
//  void _onDoneHelper(bool complete) {
//    if (!_error) {
//      completer.complete(complete);
//    }
//  }
//
//  void set onError(void onError(e)) {
//    _onError = onError;
//  }
//
//  void _onErrorHelper(e) {
//    _error = true;
//    if (_onError != null) {
//      _onError(e);
//    }
//  }
//}