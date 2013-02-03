// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library builder;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:buildtool/glob.dart';
import 'package:buildtool/src/common.dart';
import 'package:buildtool/src/symlink.dart';
import 'package:buildtool/src/utils.dart';
import 'package:buildtool/task.dart';
import 'package:logging/logging.dart';

Logger _logger = new Logger('builder');

/** Matches glob expressions starting with a task name, like "foo:*.html" */
final RegExp taskNameExp = new RegExp(r'^(\w+):');

/** A runnable build configuration */
class Builder {
  final Path sourceDirPath;
  final Path buildDir;
  final Path genDir;
  final Path outDir;

  // Use LinkedHashMap to preserve rule order for processing.
  final Map<String, _Rule> _rules = new LinkedHashMap<String, _Rule>();

  Builder(Path buildDir, Path genDir, {Path sourceDirPath})
      : sourceDirPath = (sourceDirPath == null)
            ? new Path(new Directory.current().path)
            : sourceDirPath,
        buildDir = buildDir,
        genDir = genDir,
        outDir = buildDir.append(OUT_DIR);

  /**
   * Adds a new [Task] to this builder which is run when files match against the
   * [Glob] patterns in [files].
   */
  void addRule(String name, Task task, List<String> files) {
    _logger.info("adding task $name ${task} for files $files");
    if (_rules.containsKey(name)) {
      throw new ArgumentError("Task with name $name already added");
    }
    for (var pattern in files) {
      Match match = taskNameExp.firstMatch(pattern);
      if (match != null && !_rules.containsKey(match.group(1))) {
        throw new ArgumentError("unknown task '${match.group(1)}' ${_rules}");
      }
    }
    _rules[name] = new _Rule(files, task);
  }

  /**
   * Start the builder.
   *
   * If [clean] is true, the output and gen directories are cleaned before
   * any tasks are run and tasks are run on all files, not just changed.
   *
   * TODO(justinfagnani): Currently [removedFiles] are not passed to tasks.
   */
  Future<BuildResult> build(
      List<String> changedFiles,
      List<String> removedFiles,
      {bool clean: false}) {

    _logger.info("Starting build");

    var initTasks = [];
    if (clean) {
      initTasks.addAll([_cleanDir(buildDir), _cleanDir(genDir)]);
    }
    return Future.wait(initTasks)
      .then((_) => _createDirs())
      .then((_) {
        _logger.info("Initialization tasks complete");
        // get the files to operate on
        return (changedFiles.isEmpty || clean)
            ? _getAllFiles()
            : new Future.immediate(changedFiles.where(isValidInputFile).toList());
      })
      .then((List<String> filteredFiles) {
        _logger.info("Running tasks on ${filteredFiles.length} files");
        // add the prefix '_source' to file patterns with no task prefix
        var files = filteredFiles.mappedBy((f) =>
            new InputFile(SOURCE_PREFIX, f, sourceDirPath.toString()));

        return _run(files);
      });
  }

  /**
   * Runs each task with the set of files that match it's glob entries. After
   * the tasks are run, their outputs are added to the set of changed files, in
   * case a task is configured to operate on them.
   *
   * Returns a [BuildResult] combining the results of all task runs.
   */
  Future<BuildResult> _run(Iterable<InputFile> files) {
    // copy files so we can add the output of tasks to it
    var allFiles = new List.from(files);
    var prevOutDir;

    // Run an async function on every rule that runs the rule, symlinks it's
    // output directory and updates the BuildResult. We reduce the list of
    // rules to a BuildResult, but there is only one BuildResult instance which
    // is just mutatted and passed along.
    return reduceAsync(_rules.values, new BuildResult.empty(),
        (BuildResult buildResult, _Rule rule) {

      var matches = allFiles.where((f) =>
          rule.shouldRunOn(f.matchString)).toList();
      if (matches.isEmpty) {
        // don't run the current task if we have no files to operate on
        return new Future.immediate(buildResult);
      }

      var task = rule.task;
      var taskOutDir = _taskOutDir(task);

      return _runTask(task, matches)
        .then((result) {
          _logger.info(
              "Task complete: ${task.name}\n"
              "  outputs: ${result.outputs}\n"
              "  mappings: ${result.mappings}");
          return _symlinkSources(prevOutDir, taskOutDir).then((_) => result);
        })
        .then((TaskResult taskResult) {
          buildResult.messages.addAll(taskResult.messages);
          // mappings are relative paths to the output dir, but the Editor
          // needs them relative to the project dir
          for (var file in taskResult.mappings.keys) {
            var newPath = taskOutDir.append(taskResult.mappings[file]);
            buildResult.mappings[file] = newPath.toString();
          }

          // add the outputs to files so subsequent tasks can process them
          var newFiles = taskResult.outputs.mappedBy((f) =>
              new InputFile(task.name, f, _taskOutDir(task).toString()));
          allFiles.addAll(newFiles);
          // remember this tasks output dir for symlinking
          prevOutDir = taskOutDir;

          return buildResult;
        });
    }).then((buildResult) {
      return _symlinkSources(prevOutDir, outDir).then((_) => buildResult);
    });
  }

  /** Run a [task] on [files]. */
  Future<TaskResult> _runTask(Task task, Iterable<InputFile> files) {
    var taskOutDir = _taskOutDir(task);
    return _createBuildDir(taskOutDir)
        .then((_) {
          _logger.info("Running ${task.name} on $files");
          return task.run(files, sourceDirPath, taskOutDir, genDir)
              .catchError((AsyncError e) {
                _logger.severe("Error running task ${task.name}: $e");
                throw e;
              });
        })
        .then((TaskResult result) {
          _logger.fine("task ${task.name} mappings: ${result.mappings}");
          return result;
        });
  }

  /**
   * Create a symlink from within [outDir] to within [inDir] for every file or
   * directory in [inDir] that doesn't exist in [outDir].
   *
   * This method duplicates the structure of [inDir] in [outDir]. After a task
   * writes files into it's output directory, it has created a partial
   * copy/transformation of the source tree from the previous task or source
   * dir. This method fills in the rest by walking the input directory tree and
   * symlinking any file or directory no in [outDir]. If a file exists it's
   * simply skipped. If a directory exists no symlink is created for it, but
   * it's recursed into. This will create the minimum number of symlinks to
   * recreate the source tree.
   */
  Future _symlinkSources(Path inDir, Path outDir) {
    inDir = inDir == null ? sourceDirPath : inDir;
    if (!inDir.isAbsolute) {
      inDir = new Path(new Directory.current().path).join(inDir);
    }
    _logger.fine("symlinking sources from $inDir to $outDir");
    var completer = new Completer();

    // walk the inDir tree
    var lister = new RecursiveDirectoryLister.fromPath(inDir)
      // when we see a file, symlink that file in the outDir, unless it already
      // exists
      ..onFile = (f) {
        if (!f.startsWith(inDir.toString())) {
          return;
        }
        var relativePath = f.substring(inDir.toString().length + 1);
        if (isValidInputFile(relativePath)) {
          var linkPath = outDir.append(relativePath);
          var file = new File.fromPath(outDir.append(relativePath));
          if (!file.existsSync()) {
            // TODO(justinfagnani): how do we validate the file? could it be a
            // broken symlink?
            createSymlink(f, linkPath.toString());
          }
        }
      }
      // When we see a dir, symlink it unless it exists in the output. If it
      // exists in the output, recurse into it.
      ..onDir = (d) {
        if (!d.startsWith(inDir.toString())) {
          // this must be from a symlink outside the directory
          // we should already be skipping this because we know we symlinked it
          // in a previous pass, but right now we'll skip it here
          return false;
        }
        var relativePath = d.substring(inDir.toString().length + 1);
        _logger.fine("relative path: $relativePath");
        if (!isValidInputFile(relativePath)) {
          return false;
        }
        var linkPath = outDir.append(relativePath);

        var dir = new Directory.fromPath(linkPath);
        var file = new File.fromPath(linkPath);

        if (dir.existsSync()) {
          // TODO(justinfagnani): check that dir is not a symlink
          // recurse so we can symlink files/dirs further down in the tree
          // unless it's the packages symlink
          return !d.endsWith("packages");
        } else {
          createSymlink(d, linkPath.toString());
          return false;
        }
      }
      ..onDone = (s) {
        completer.complete(null);
      }
      ..onError = (e) {
        completer.completeError(e);
      };
    return completer.future;
  }

  /** Creates the output and gen directories */
  Future _createDirs() => _createDir(buildDir).then((_) =>
      Future.wait([_createBuildDir(outDir), _createDir(genDir)]));

  /** Creates the output directory and adds a packages/ symlink */
  Future _createBuildDir(Path buildDirPath) {
    var dir = new Directory.fromPath(buildDirPath);

    return dir.exists().then((exists) {
      var create = (exists) ? new Future.immediate(true) : dir.create();
      return create.then((_) {
        // create pub symlink
        var linkPath = buildDirPath.append(PACKAGES).toNativePath();
        if (!dirSymlinkExists(linkPath)) {
          removeBrokenDirSymlink(linkPath);
          var targetPath = new File(PACKAGES).fullPathSync();
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
    return dir.exists().then((exists) =>
        (exists)
            ? new Future.immediate(true)
            : dir.create().then((_) => true));
  }

  /** Cleans the given directory */
  Future<bool> _cleanDir(Path dirPath) {
    var dir = new Directory.fromPath(dirPath);
    return dir.exists().then((exists) =>
        (exists)
            ? dir.delete(recursive: true).then((_) => true)
            : new Future.immediate(false));
  }

  Future<List<String>> _getAllFiles() {
    var files = <String>[];
    var completer = new Completer<List<String>>();
    var lister = new RecursiveDirectoryLister.fromPath(sourceDirPath)
      ..onDir = (String dir) {
        return !dir.endsWith(PACKAGES);
      }
      ..onFile = (file) {
        var relativePath = new Path(file).relativeTo(sourceDirPath);
        files.add(relativePath.toString());
      }
      ..onDone = (s) {
        completer.complete(files);
      }
      ..onError = completer.completeError;
    return completer.future;
  }

  Path _taskOutDir(Task task) => buildDir.append('_${task.name}');
}

class BuildResult {
  final List<String> messages;
  final Map<String, String> mappings;

  BuildResult(this.messages, this.mappings);
  BuildResult.empty() : messages = <String>[], mappings = <String, String>{};
}

class _Rule {
  final List<String> files;
  final Task task;
  List<Glob> patterns;

  _Rule(this.files, this.task) {
    patterns = files.mappedBy((f) {
      // If the file pattern doesn't contain a task name prefix, add '_source:'
      // to indicate that it matches against the original source tree. Forcing
      // a prefix restricts patterns to match only one task, and prevents
      // patterns like '**/a.html' from matching outputs from all tasks. We can
      // relax this restriction later if necessary.
      var patternString = taskNameExp.hasMatch(f) ? f : '$SOURCE_PREFIX:$f';
      return new Glob(patternString);
    }).toList();
  }

  bool shouldRunOn(String filename) =>
      patterns.any((p) => p.hasMatch(filename));
}
