// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library symlink;

import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';

Logger _logger = new Logger('symlink');

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
          var path;
          if (e is Directory) {
            path = new Path(e.path);
            var expectedFullPath = fullParentPath.append(path.filename).toString();
            var fullPath = new Path(new File.fromPath(path).fullPathSync());

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
            path = new Path(e.name);
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
  var fullPath = new Path(new File(dir.path).fullPathSync());
  _list(dir, fullPath);

  return controller.stream;
}

class Symlink extends FileSystemEntity {
  final String target;
  final String link;
  final bool isDirectory;

  Symlink(this.target, this.link, {this.isDirectory});

  // TODO(justinfagnani): this code was taken from dwc, from Pub's io library.
  // Added error handling and don't return the file result, to match the code
  // we had previously. Also "from" and "to" only accept paths. And inlined
  // the relevant parts of runProcess. Note that it uses "cmd" to get the path
  // on Windows.
  /**
   * Creates a new symlink that creates an alias from [link] -> [target].
   */
  Future create() {
    var command = 'ln';
    var args = ['-s', target, link];

    if (Platform.operatingSystem == 'windows') {
      // Call mklink on Windows to create an NTFS junction point. Only works on
      // Vista or later. (Junction points are available earlier, but the "mklink"
      // command is not.) I'm using a junction point (/j) here instead of a soft
      // link (/d) because the latter requires some privilege shenanigans that
      // I'm not sure how to specify from the command line.
      command = 'cmd';
      args = ['/c', 'mklink', '/j', link, target];
    }

    return Process.run(command, args).then((result) {
      if (result.exitCode != 0) {
        var message = 'unable to create symlink\n'
                      '  target: $target\n'
                      '  link:$link\n'
                      '  subprocess stdout:\n${result.stdout}\n'
                      '  subprocess stderr:\n${result.stderr}';
        _logger.severe(message);
        throw new RuntimeError(message);
      }
      return null;
    });
  }

  String toString() => "Symlink: '$target' '$link'";
}

/**
 * Returns [true] if [linkPath] is a directory, since symlinks act like
 * directories.
 */
bool dirSymlinkExists(String linkPath) => new Directory(linkPath).existsSync();

/**
 * If [linkPath] is a file, deletes it, since broken symlinks act like a file.
 */
removeBrokenDirSymlink(String linkPath) {
  var toFile = new File(linkPath);
  if (toFile.existsSync()) {
    toFile.deleteSync();
  }
}
