// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of buildtool.util.io;

class Symlink extends FileSystemEntity {
  final String target;
  final String link;
  final bool isDirectory;

  Symlink(this.target, this.link, {this.isDirectory});

  String get path => link;
  
  // TODO(justinfagnani): this code was taken from dwc, from Pub's io library.
  // Added error handling and don't return the file result, to match the code
  // we had previously. Also "from" and "to" only accept paths. And inlined
  // the relevant parts of runProcess. Note that it uses "cmd" to get the path
  // on Windows.
  /**
   * Creates a new symlink that creates an alias from [link] -> [target].
   */
  Future create({bool noDeference: false, bool force: false}) {
    var command = 'ln';
    var n = noDeference ? 'n' : '';
    var f = force ? 'f' : '';
    var args = ['-s$n$f', target, link];

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
                      '  link: $link\n'
                      '  subprocess stdout: ${result.stdout}\n'
                      '  subprocess stderr: ${result.stderr}';
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
