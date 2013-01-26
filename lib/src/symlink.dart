// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library symlink;

import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';

Logger _logger = new Logger('symlink');

// TODO(justinfagnani): this code was taken from dwc, from Pub's io library.
// Added error handling and don't return the file result, to match the code
// we had previously. Also "from" and "to" only accept paths. And inlined
// the relevant parts of runProcess. Note that it uses "cmd" to get the path
// on Windows.
/**
 * Creates a new symlink that creates an alias from [target] -> [to].
 */
Future createSymlink(String target, String linkPath) {
  var command = 'ln';
  var args = ['-s', target, linkPath];

  if (Platform.operatingSystem == 'windows') {
    // Call mklink on Windows to create an NTFS junction point. Only works on
    // Vista or later. (Junction points are available earlier, but the "mklink"
    // command is not.) I'm using a junction point (/j) here instead of a soft
    // link (/d) because the latter requires some privilege shenanigans that
    // I'm not sure how to specify from the command line.
    command = 'cmd';
    args = ['/c', 'mklink', '/j', linkPath, target];
  }

  return Process.run(command, args).then((result) {
    if (result.exitCode != 0) {
      var details = 'subprocess stdout:\n${result.stdout}\n'
                    'subprocess stderr:\n${result.stderr}';
      _logger.severe(
        'unable to create symlink\n from: $target\n to:$linkPath\n$details');
    }
    return null;
  });
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
