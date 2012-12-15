// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.


library builder;

import 'dart:io';
import 'package:buildtool/glob.dart';
import 'package:buildtool/src/common.dart';
import 'package:buildtool/src/symlink.dart';
import 'package:buildtool/src/utils.dart';
import 'package:buildtool/task.dart';
import 'package:logging/logging.dart';

Logger _logger = new Logger('builder');

/** 
 * Maximum number of times that the tasks are run on the output of previous
 * passes.
 * 
 * TODO: Base task execution on the dependency graph and disallow cycles.
 */
final int MAX_PASSES = 5;

/** A runnable build configuration */
class Builder {
  final List<_Rule> _rules = <_Rule>[];
  
  final Path buildDir;
  final Path genDir;
  
  Builder(this.buildDir, this.genDir);
  
  Path get outDir => buildDir.append(OUT_DIR);

  /**
   * Adds a new [Task] to this builder which is run when files
   * match against the regex patterns in [files].
   */
  void addTask(List<String> files, Task task) {
    _logger.info("adding task ${task} for files $files");
    _rules.add(new _Rule(files, task));
  }
  
  /** 
   * Start the builder.
   * If [cleanBuild] is true, the output and gen directories are cleaned
   * before any tasks are run.
   *  
   * TODO(justinfagnani): Currently [removedFiles] are not passed to tasks.
   */
  Future<BuildResult> build(
      List<String> changedFiles,
      List<String> removedFiles,
      bool cleanBuild) {
    
    _logger.info("starting build");
    
    var initTasks = [];
    if (cleanBuild) {
      initTasks.addAll([_cleanDir(buildDir), _cleanDir(genDir)]);
    }
    return Futures.wait(initTasks)
      .chain((_) => _createDirs())
      .chain((_) {
        return (changedFiles.isEmpty)
            ? _getAllFiles()
            : new Future.immediate(changedFiles.filter(isValidInputFile));
      })
      .chain((List<String> filteredFiles) {
        var inputFiles = filteredFiles.map((f) => 
            new InputFile(SOURCE_PREFIX, f));
        return _runTasks(inputFiles);
      });
  }
  
  /**
   * Runs each task with the set of files that match it's glob entries. After
   * the tasks are run, their outputs are run through the tasks again, in
   * case a task is configured to operate on them. The process stops when there
   * are no outputs, or when the max [depth] is reached (currently 5).
   * 
   * Returns a [BuildResult] combining the results of all task runs.
   */
  Future<BuildResult> _runTasks(List<InputFile> files, {depth: 0}) {
    
    _logger.fine("_runTasks: $files");
    
    if (depth > MAX_PASSES) {
      return new Future.immediate(new BuildResult([], {}));
    }
    
    var completer = new Completer();
    var futures = [];
    
    // run all the tasks
    for (var rule in _rules) {
      var matches = files.filter((f) => rule.shouldRunOn(f.matchString));
      if (!matches.isEmpty) {
        var taskOutDir = _taskOutDir(rule.task);
        futures.add(_createBuildDir(taskOutDir)
            .chain((_) => rule.task.run(matches, taskOutDir, genDir))
            .transform((r) => new _TaskAndResult(rule.task, r)));
      }
    }
    
    // process the results
    Futures.wait(futures).then((List<_TaskAndResult> results) {
      _logger.fine("tasks at depth $depth complete");
      var messages = [];
      var mappings = new Map<String, String>();
      var newFiles = <InputFile>[];
      
      for (var taskAndResult in results) {
        var task = taskAndResult.task;
        var result = taskAndResult.result;
        
        newFiles.addAll(result.outputs.map((f) {
          return new InputFile(task.name, f, dir: _taskOutDir(task).toString());
        }));
        
        messages.addAll(result.messages);
        for (var source in result.mappings.keys) {
          mappings[source] = result.mappings[source];
        }
      }
      
      if (newFiles.isEmpty) {
        completer.complete(new BuildResult(messages, mappings));
      } else {
        _logger.fine("new files to be processed: $newFiles");
        _runTasks(newFiles, depth: depth + 1).then((buildResult) {
          messages.addAll(buildResult.messages);
          var allMappings = mergeMaps([mappings, buildResult.mappings]);
          completer.complete(new BuildResult(messages, allMappings));
        });
      }
    });
    return completer.future;
  }
  
  /** Creates the output and gen directories */
  Future _createDirs() => _createDir(buildDir).chain((_) => 
      Futures.wait([_createBuildDir(outDir), _createDir(genDir)]));

  /** Creates the output directory and adds a packages/ symlink */
  Future _createBuildDir(Path buildDirPath) {
    var cwd = new Directory.current().path;
    _logger.info("cwd: $cwd $buildDirPath");
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
        } else {
          return new Future.immediate(null);
        }
      });
    });
  }

  /** Creates the gen directory */
  Future<bool> _createDir(Path buildDirPath) {
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
  
  Future<List<String>> _getAllFiles() {
    var cwd = new Directory.current().path;
    var futureGroup = new FutureGroup();
    var files = <String>[];
    var _error = false;
    onDir(String dir) {
      if (!_error && !dir.endsWith("packages")) {
        var completer = new Completer();
        futureGroup.add(completer.future);
        new Directory(dir).list()
        ..onFile = (file) { 
          if (!_error) files.add(file.substring(cwd.length + 1));
        }
        ..onDir = onDir
        ..onDone = (s) {
          if (!_error) completer.complete(null);
        }
        ..onError = (e) {
          _error = true;
          completer.completeException(e);
        };
       }
     }
    getFiles(List<String> dirs) {
      dirs.forEach((dir) {
        new Directory(dir).exists().then((exists) {
          if (exists) onDir(dir);
        });
      });
    }
    getFiles(['web', 'lib', 'bin']);
    return futureGroup.future.transform((_) => files);
  }
  
  Path _taskOutDir(Task task) => buildDir.append('_${task.name}');
}

class BuildResult {
  final List<String> messages;
  final Map<String, String> mappings;
  
  BuildResult(this.messages, this.mappings);
}

final RegExp taskNameExp = new RegExp(r'^\w+:');

class _Rule {
  final List<String> files;
  final Task task;
  List<Glob> patterns;
  
  _Rule(this.files, this.task) {
    patterns = files.map((f) {
      // If the file pattern doesn't contain a task name prefix, add '_source:'
      // to indicate that it matches against the original source tree. Forcing
      // a prefix restricts patterns to match only one task, and prevents
      // patterns like '**/a.html' from matching outputs from all tasks. We can
      // relax this restriction later if necessary.
      var patternString = taskNameExp.hasMatch(f) ? f : '$SOURCE_PREFIX:$f';
      return new Glob(patternString);
    });
  }
  
  bool shouldRunOn(String filename) => 
      patterns.some((p) => p.hasMatch(filename));
}

class _TaskAndResult {
  final Task task;
  final TaskResult result;
  _TaskAndResult(this.task, this.result);
}

