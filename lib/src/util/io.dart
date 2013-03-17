// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library buildtool.util.io;

import 'dart:async';
import 'dart:io';
import 'dart:uri';
import 'package:logging/logging.dart';
import 'package:buildtool/src/util/future_group.dart';

part 'symlink.dart';

Logger _logger = new Logger('io');

String uriToNativePath(Uri uri) {
  if (uri.scheme != 'file') {
    throw new ArgumentError(uri);
  }
  return new Path(uri.path).toNativePath();
}

Future<String> byteStreamToString(Stream<List<int>> stream) =>
    stream.transform(new StringDecoder()).toList().then((l) => l.join(''));

Path getFullPath(path) =>
    new Path(((path is Path) ? new File.fromPath(path) : new File(path))
        .fullPathSync());

/**
 * Lists the sub-directories and files of this Directory. Optionally recurses
 * into sub-directories based on the return value of [visit].
 * [visit] is called with a [File], [Directory] or [Symlink] to a directory,
 * never a Symlink to a File. If [visit] returns true, then it's argument is
 * listed recursively.
 *
 * Please see [Symlink], which is a [FileSystemEntity] subclass that this
 * library introduces.
 */
Future visitDirectory(Directory dir, Future<bool> visit(FileSystemEntity f)) {
  var futureGroup = new FutureGroup();
  
  void _list(Directory dir, Path fullParentPath) {
    var listCompleter = new Completer();
    futureGroup.add(listCompleter.future);
    var sub;
    sub = dir.list().listen((FileSystemEntity e) {
      var path = new Path(e.path);
      var expectedFullPath = fullParentPath.append(path.filename).toString();
      var fullPath = getFullPath(path);
      var entity = (fullPath.toString() != expectedFullPath.toString())
          ? new Symlink(fullPath.toString(), path.toString(),
              isDirectory: e is Directory)
          : e;
      var future = visit(entity);
      if (future != null) {
        futureGroup.add(future.then((bool recurse) {
          // recurse on directories, but not cyclic symlinks
          if (e is Directory && recurse == true &&
              !(fullParentPath.toString().startsWith(fullPath.toString()))) {
            _list(e, fullPath);
          }
        }));
      }
    },
    onError: (AsyncError e) {
      var error = e.error;
      if (error is DirectoryIOException) {
        // must be a broken symlink. error.path is local path
        futureGroup.add(visit(new Symlink(null, error.path)));
      } else {
        listCompleter.completeError(e);
        sub.cancel();
      }
    },
    onDone: () { listCompleter.complete(null); },
    unsubscribeOnError: false);
  }
  _list(dir, getFullPath(dir.path));

  return futureGroup.future;
}
