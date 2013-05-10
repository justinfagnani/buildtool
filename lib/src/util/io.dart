// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library buildtool.util.io;

import 'dart:async';
import 'dart:io';
import 'dart:uri';
import 'package:logging/logging.dart';
import 'package:buildtool/src/util/future_group.dart';

Logger _logger = new Logger('io');

String uriToNativePath(Uri uri) {
  if (uri.scheme != 'file') {
    throw new ArgumentError(uri);
  }
  return new Path(uri.path).toNativePath();
}

Future<String> byteStreamToString(Stream<List<int>> stream) =>
    stream.transform(new StringDecoder()).toList().then((l) => l.join());

Path getFullPath(path) =>
    new Path(((path is Path) ? new File.fromPath(path) : new File(path))
        .fullPathSync());

typedef void F(bool b, bool a(String s));

/**
 * Lists the sub-directories and files of this Directory. Optionally recurses
 * into sub-directories based on the return value of [visit].
 * [visit] is called with a [File], [Directory] or [Link] to a directory,
 * never a Symlink to a File. If [visit] returns true, then it's argument is
 * listed recursively.
 */
Future visitDirectory(Directory dir, Future<bool> visit(FileSystemEntity f)) {
  var futureGroup = new FutureGroup();

  void _list(Directory dir) {
    var completer = new Completer();
    futureGroup.add(completer.future);
    var sub;
    sub = dir.list(followLinks: false).listen((FileSystemEntity entity) {
      var future = visit(entity);
      if (future != null) {
        futureGroup.add(future.then((bool recurse) {
          // recurse on directories, but not cyclic symlinks
          if (entity is! File && recurse == true) {
            if (entity is Link) {
              if (FileSystemEntity.typeSync(entity.path, followLinks: true) ==
                    FileSystemEntityType.DIRECTORY) {
                var fullPath = getFullPath(entity.path).toString();
                var dirFullPath = getFullPath(dir.path).toString();
                if (!dirFullPath.startsWith(fullPath)) {
                  _list(new Directory(entity.path));
                }
              }
            } else {
              _list(entity);
            }
          }
        }));
      }
    },
    onDone: () {
      completer.complete(null);
    },
    cancelOnError: true);
  }
  _list(dir);

  return futureGroup.future;
}
