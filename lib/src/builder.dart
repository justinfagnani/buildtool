// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.


library builder;

import 'dart:io';
import 'package:buildtool/glob.dart';
import 'package:buildtool/src/symlink.dart';
import 'package:buildtool/task.dart';
import 'package:logging/logging.dart';

Logger _logger = new Logger('builder');

/** A runnable build configuration */
class Builder {
  final List<_TaskEntry> _tasks = <_TaskEntry>[];
  
  final Path outDir;
  final Path genDir;
  
  Builder(this.outDir, this.genDir);
  
  /**
   * Adds a new [Task] to this builder which is run when files
   * match against the regex patterns in [files].
   */
  void addTask(List<String> files, Task task) {
    _tasks.add(new _TaskEntry(files, task));
  }
  
  /** 
   * Start the builder.
   * If [cleanBuild] is true, the output and gen directories are cleaned
   * before any tasks are run.
   *  
   * TODO(justinfagnani): Currently [removedFiles] are not passed to tasks.
   */
  Future build(
      List<String> changedFiles,
      List<String> removedFiles,
      bool cleanBuild) {
    
    _logger.info("Starting build...");
    
    // ignore inputs in the ouput dir that the Editor forwards
    var filteredFiles = 
        changedFiles.filter((f) => !f.startsWith(outDir.toString()));
    
    var initTasks = [];
    if (cleanBuild) {
      initTasks.addAll([_cleanDir(outDir), _cleanDir(genDir)]);
    }
    return Futures.wait(initTasks)
      .chain((_) => _createDirs())
      .chain((_) {
        var futures = [];
        for (var entry in _tasks) { // TODO: parallelize
          var matches = filteredFiles.filter(entry.matches);
          var paths = matches.map((f) => new Path(f));
          futures.add(entry.task.run(paths, outDir, genDir));
        }
        return Futures.wait(futures);
      })
      .transform((results) {
        _logger.info("Build finished");
        return true;
      });
  }
  
  /** Creates the output and gen directories */
  Future _createDirs() => 
      Futures.wait([_createBuildDir(outDir), _createGenDir(genDir)]);

  /** Creates the output directory and adds a packages/ symlink */
  Future _createBuildDir(Path buildDirPath) {
    var dir = new Directory.fromPath(buildDirPath);
    
    return dir.exists().chain((exists) {
      var create = (exists) ? new Future.immediate(true) : dir.create();
      return create.chain((_) {
        // create pub symlink
        var linkPath = buildDirPath.append('packages').toNativePath();
        if (!dirSymlinkExists(linkPath)) {
          removeBrokenDirSymlink(linkPath);
          var targetPath = new File('packages').fullPathSync();
          return createSymlink(targetPath, linkPath);
        }
      });
    });
  }

  /** Creates the gen directory */
  Future<bool> _createGenDir(Path buildDirPath) {
    var dir = new Directory.fromPath(buildDirPath);
    return dir.exists().chain((exists) =>
        (exists) 
            ? new Future.immediate(true) 
            : dir.create().transform((_) => true));
  }
  
  /** Cleans the given directory */
  Future<bool> _cleanDir(Path dirPath) {
    var dir = new Directory.fromPath(dirPath);
    return dir.exists().chain((exists) =>
        (exists)
            ? dir.delete(recursive: true).transform((_) => true)
            : new Future.immediate(false));
  }
}

class _TaskEntry {
  final List<String> files;
  final Task task;
  List<Glob> patterns;
  
  _TaskEntry(this.files, this.task) {
    patterns = files.map((f) => new Glob(f));
  }
  
  bool matches(String filename) => patterns.some((p) => p.hasMatch(filename));
}
