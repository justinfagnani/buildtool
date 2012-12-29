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
  final Path sourceDirPath;
  final Path buildDir;
  final Path genDir;
  final Path outDir;
  
  final Map<String, _Rule> _rules = new LinkedHashMap<String, _Rule>();
  final _taskQueue = new Queue<_ScheduledTask>();
  
  Builder(Path buildDir, Path genDir, {Path sourceDirPath})
      : sourceDirPath = (sourceDirPath == null) 
            ? new Path(new Directory.current().path)
            : sourceDirPath,
        buildDir = buildDir,
        genDir = genDir,
        outDir = buildDir.append(OUT_DIR);
  
  /**
   * Adds a new [Task] to this builder which is run when files
   * match against the regex patterns in [files].
   */
  void addRule(String name, Task task, List<String> files) {
    _logger.info("adding task ${task} for files $files");
    if (_rules.containsKey(name)) {
      throw new ArgumentError("Task with name $name already added");
    }
    _rules[name] = new _Rule(files, task);
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
        var files = filteredFiles.map((f) => new InputFile(SOURCE_PREFIX, f));
        // Queue up the initial set of tasks that match on source files
        _queueTasks(files);
        return _run();
      });
//      .chain((BuildResult) {
//        // symlink the final output directory
////        _symlinkSources
//      });
  }
  
  /**
   * Runs each task with the set of files that match it's glob entries. After
   * the tasks are run, their outputs are run through the tasks again, in
   * case a task is configured to operate on them. The process stops when there
   * are no outputs, or when the max [depth] is reached (currently 5).
   * 
   * Returns a [BuildResult] combining the results of all task runs.
   */
  Future<BuildResult> _run({Path previousOutDir, int count: 0}) {
    if (!_taskQueue.isEmpty && count < MAX_PASSES) {
      var scheduledTask = _taskQueue.removeFirst();
      var task = scheduledTask.task;
      var files = scheduledTask.files;
      var taskOutDir = _taskOutDir(task);
      
      return _runTask(task, files)
          .chain((TaskResult result) {
            return _symlinkSources(previousOutDir, taskOutDir)
                .transform((_) => result);
          })
          .chain((TaskResult result) {
            assert(result != null);
            var messages = new List.from(result.messages);
            var mappings = new Map<String, String>();
            // mappings are relative paths to the output dir, but the Editor
            // needs them relative to the project dir
            for (var file in result.mappings.keys) {
              var newPath = taskOutDir.append(result.mappings[file]);
              mappings[file] = newPath.toString();
            }
            
            var newFiles = result.outputs.map((f) =>
                new InputFile(task.name, f, dir: _taskOutDir(task).toString()));
    
            _queueTasks(newFiles);
            
            return _run(previousOutDir: taskOutDir, count: count + 1)
                .transform((BuildResult result) {
                  messages.addAll(result.messages);
                  var allMappings = mergeMaps([mappings, result.mappings]);
                  return new BuildResult(messages, mappings);
                });
          });
    } else {
      return _symlinkSources(previousOutDir, outDir)
          .transform((_) => new BuildResult([], {}));
    }
  }
  
  /** Add all tasks that should run on [files] to the task queue. */
  _queueTasks(files) {
    for (var rule in _rules.values) {
      var matches = files.filter((f) => rule.shouldRunOn(f.matchString));
      if (!matches.isEmpty) {
        _taskQueue.add(new _ScheduledTask(rule.task, matches));
      }
    }
  }
  
  /** Run a [task] on [files]. */
  Future<TaskResult> _runTask(Task task, Iterable<InputFile> files) {
    var taskOutDir = _taskOutDir(task);
    return _createBuildDir(taskOutDir)
        .chain((_) => task.run(files, taskOutDir, genDir))
        .transform((TaskResult result) {
          _logger.fine("task ${task.name} mappings: ${result.mappings}");
          return result;
        });
  }
  
  Future _symlinkSources(Path inDir, Path outDir) {
    inDir = inDir == null ? sourceDirPath : inDir;
    if (!inDir.isAbsolute) {
      inDir = new Path(new Directory.current().path).join(inDir);
    }
    _logger.fine("symlinking sources from $inDir to $outDir");
    var completer = new Completer();
    
    // we walk the inDir tree
    var lister = new RecursiveDirectoryLister.fromPath(inDir)
      // when we see a file (TODO: which might be a broken dir symlink)
      // symlink that file in the outDir, unless it already exists
      ..onFile = (f) {
        var relativePath = f.substring(inDir.toString().length + 1);
        _logger.fine("looking at file $relativePath ${isValidInputFile(relativePath)}");
        if (isValidInputFile(relativePath)) {
          var linkPath = outDir.append(relativePath);
          var file = new File.fromPath(outDir.append(relativePath));
          if (!file.existsSync()) {
            // TODO: how do we validate the file? could it be a broken symlink?
            createSymlink(f, linkPath.toString());
          } else {
            _logger.fine("file exists: $relativePath");
          }
        }
      }
      // when we see a dir, symlink it unless it exists
      // if it exists, recurse
      ..onDir = (d) {
        var relativePath = d.substring(inDir.toString().length + 1);
        if (d.endsWith("packages") || !isValidInputFile(relativePath)) {
          return false;
        }
        _logger.fine("looking at dir $relativePath");
        var linkPath = outDir.append(relativePath);
        
        var dir = new Directory.fromPath(linkPath);
        var file = new File.fromPath(linkPath);
        
        if (dir.existsSync()) {
          // TODO: check that dir it not a symlink
          // recurse so we can symlink files/dirs further down in the tree
          _logger.fine("dir exists: $relativePath");
          return true;
        } else {
          createSymlink(d, linkPath.toString());
          return false;
        }
      }
      ..onDone = (s) {
        completer.complete(null);
      }
      ..onError = (e) {
        completer.completeException(e);
      };
    return completer.future;
  }
  
  /** Creates the output and gen directories */
  Future _createDirs() => _createDir(buildDir).chain((_) => 
      Futures.wait([_createBuildDir(outDir), _createDir(genDir)]));

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
    var files = <String>[];
    var completer = new Completer<List<String>>();
    var lister = new RecursiveDirectoryLister.fromPath(sourceDirPath)
      ..onDir = ((String dir) => !dir.endsWith("packages"))
      ..onFile = (file) {
        files.add(file.substring(sourceDirPath.toString().length + 1));
      }
      ..onDone = (s) {
        completer.complete(files);
      }
      ..onError = completer.completeException;
    return completer.future;    
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

//class _TaskAndResult {
//  final Task task;
//  final TaskResult result;
//  _TaskAndResult(this.task, this.result);
//}

class _ScheduledTask {
  final Task task;
  final Iterable<InputFile> files;
  
  _ScheduledTask(this.task, this.files);
}
