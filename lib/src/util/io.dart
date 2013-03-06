// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library buildtool.util.io;

import 'dart:async';
import 'dart:io';
import 'dart:uri';
import 'package:logging/logging.dart';

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
    new Path(((path is Path) 
        ? new File.fromPath(path)
        : new File(path)).fullPathSync());

/**
 * Lists the sub-directories and files of this Directory. Optionally recurses
 * into sub-directories based on the return value of the [recurse] parameter.
 * [recurse] is called with either a [Directory] or a [Symlink] that is linked
 * to a directory. If [recurse] returns true, then it's argument is listed.
 *
 * The result is a stream of FileSystemEntity objects for the directories,
 * files, and symlinks. Please see [Symlink], which is a [FileSystemEntity]
 * subclass that this library introduces.
 */
Stream<FileSystemEntity> listDirectory(Directory dir,
    bool recurse(FileSystemEntity dir)) {
  var controller = new StreamController<FileSystemEntity>();
  int openStreamCount = 0;

  void _list(Directory _dir, Path fullParentPath) {
    var stream = _dir.list();
    openStreamCount++;
    StreamSubscription sub;
    sub = stream.listen(
        (FileSystemEntity e) {
          var path = new Path(e.path);
          if (e is Directory) {
            var expectedFullPath = fullParentPath.append(path.filename).toString();
            var fullPath = getFullPath(path);

            if (fullPath.toString() != expectedFullPath.toString()) {
              controller.add(new Symlink(fullPath.toString(), path.toString(),
                  isDirectory: true));
            } else {
              controller.add(e);
            }
            if (recurse(e) &&
                !(fullParentPath.toString().startsWith(fullPath.toString()))) {
              _list(e, fullPath);
            }
          } else if (e is File) {
            var expectedFullPath = fullParentPath.append(path.filename).toString();
            var fullPath = e.fullPathSync();

            if (fullPath.toString() != expectedFullPath.toString()) {
              controller.add(new Symlink(fullPath.toString(), path.toString()));
            } else {
              controller.add(e);
            }
          }
        },
        onError: (AsyncError e) {
          var error = e.error;
          if (error is DirectoryIOException) {
            // must be a broken symlink. error.path is local path
            controller.add(new Symlink(null, error.path));
          } else {
            controller.signalError(e);
            sub.cancel();
          }
        },
        onDone: () {
          openStreamCount--;
          if (openStreamCount == 0) {
            controller.close();
          }
        },
        unsubscribeOnError: false);
  }
  _list(dir, getFullPath(dir.path));

  return controller.stream;
}
