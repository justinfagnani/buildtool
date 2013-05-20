// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library builder;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:buildtool/glob.dart';
import 'package:buildtool/src/common.dart';
import 'package:buildtool/src/util/async.dart';
import 'package:buildtool/src/util/future_group.dart';
import 'package:buildtool/src/util/io.dart';
import 'package:buildtool/task.dart';
import 'package:logging/logging.dart';

Logger _logger = new Logger('builder');

/** Matches glob expressions starting with a task name, like "foo:*.html" */
final RegExp taskNameExp = new RegExp(r'^(\w+):');

/** A runnable build configuration */
class Builder {
  final Path basePath;
  Path buildDir;
  Path genDir;
  Path outDir;
  Path deployDir;

  // Use LinkedHashMap to preserve rule order for processing.
  final Map<String, _Rule> _rules = new LinkedHashMap<String, _Rule>();

  /**
   * Create a new Builder instance.
   *
   * [buildDir], [genDir] and [deployDir] are relative to [basePath], unless
   * they are absolute. [basePath] defaults to the current working directory if
   * not specified.
   */
  Builder(Path buildDir, Path genDir, Path deployDir, {Path basePath})
      : basePath = (basePath == null)
            ? new Path(Directory.current.path)
            : basePath {

    this.buildDir = (buildDir.isAbsolute)
        ? buildDir : this.basePath.join(buildDir);
    this.genDir = (genDir.isAbsolute) ? genDir : this.basePath.join(genDir);
    this.outDir = this.buildDir.append(OUT_DIR);
    this.deployDir = (deployDir.isAbsolute)
        ? deployDir : this.buildDir.join(deployDir);
  }

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
      { bool clean: false,
      bool deploy: false}) {

    _logger.fine("Starting build deploy: $deploy");

    var initTasks = [];
    if (clean) {
      initTasks.addAll([_cleanDir(buildDir), _cleanDir(genDir)]);
    }
    return Future.wait(initTasks)
      .then((_) => _createDirs())
      .then((_) {
        _logger.fine("Initialization tasks complete");
        // get the files to operate on
        return (changedFiles.isEmpty || clean)
            ? _getAllFiles()
            : changedFiles.where(isValidInputFile);
      })
      .then((Iterable<String> filteredFiles) {
        _logger.info("Running tasks on ${filteredFiles.length} files");
        // add the prefix '_source' to file patterns with no task prefix
        var files = filteredFiles.map((f) =>
            new InputFile(SOURCE_PREFIX, f, basePath.toString()));

        return _build(files);
      })
      .then((result) {
        if (deploy) {
          _logger.info("building deploy dir.");
          return _deploy().then((_) {
            _logger.info("finished building deploy dir");
            return result;
          });
        } else {
          return result;
        }
      });
  }

  /**
   * Copy all files from the output directory to the deploy directory to create
   * a deployable set of files that can be easily tar'ed or zipped and copied.
   *
   * Known Issues:
   *  * The deploy operation copies all packages, even those included
   *    transitively by buildtool, this creates a larger deploy directory than
   *    necessary.
   *  * Internal symlinks are not handled, they will cause duplication of files.
   */
  Future<bool> _deploy() {
    Path _getRelativePath(String p) {
      if (p.startsWith(buildDir.toString())) {
        var segments = new Path(p).relativeTo(buildDir).segments();
        segments = segments.sublist(1, segments.length - 1);
        return new Path(segments.join('/'));
      } else if (p.startsWith(basePath.toString())) {
        return new Path(p).relativeTo(basePath);
      }
    }
    return _cleanDir(deployDir)
      .then((_) => _createDir(deployDir))
      .then((_) {
        _logger.fine("deployDir: $deployDir");
        var futureGroup = new FutureGroup();
        var completer = new Completer();
        futureGroup.add(completer.future);

        visitDirectory(new Directory.fromPath(outDir), (e) {
          var relativePath = new Path(e.path).relativeTo(outDir);
          var newPath = deployDir.join(relativePath);

          if (e is File) {
            _logger.fine("copying file ${e.path} to $newPath");
            // copy file
            new File.fromPath(newPath).writeAsBytesSync(e.readAsBytesSync());
            return new Future.value(false);

          } else if (e is Directory) {
            _logger.fine("copying dir ${e.path} to $newPath");
            // TODO(justinfagnani): skip dev-only package dependcies
            var copy = new Directory.fromPath(newPath);
            copy.createSync();
            return new Future.value(true);

          } else if (e is Link) {
            var target = e.targetSync();
            var linkType = FileSystemEntity.typeSync(target, followLinks: true);
            if (linkType == FileSystemEntityType.NOT_FOUND) {
              return new Future.value(false);
            }
            // There are 3 cases of symlinks in build_out/out:
            //  1. A symlink to a file in the source tree at the same relative
            //     location. This represent a normal source file or directory.
            //     Copy it and recurse.
            //  2. A symlink to a file outside the source tree, mostly likely
            //     a package. This is a dependency, copy it and recurse.
            //  3. A symlink to a file in the source tree at a different
            //     relative location, usually a packages symlink. This is an
            //     internal link, so replicate it. Don't recurse.
            
            // Whether the target is in the source tree
            bool targetInProject = target.startsWith(basePath.toString());
            
            // The relative path within the out directory
            var relativeLinkPath = new Path(e.path).relativeTo(outDir);
            
            // The relative path within the source directory
            var relativeTargetPath = _getRelativePath(target);
            
            // If the relative paths are the same, and the target is in the
            // source tree, then it's a link to an original dir in the source
            // tree (case #1) and we should recurse to copy the subtree.
            // If the relative paths are different it's an internal link (case 
            // #3) and we should replicate the link, but not recurse.
            // This applies to all packages symlinks.
            
            if (relativeLinkPath.toString() == relativeTargetPath.toString()
                || !targetInProject) {
              // Case #1 and #1
              new Directory.fromPath(newPath).createSync();
              return new Future.value(true); // recurse
            } else {
              // Case #3
              _logger.fine("skipping internal link: $e\n"
                    "  $relativeTargetPath $relativeLinkPath");
              var future = new Link.fromPath(relativePath)
                  .create(relativeTargetPath.toNativePath());
              futureGroup.add(future);
              return future.then((_) => false); // don't recurse
            }
          }
        });
      });
  }

  /**
   * Runs each task with the set of files that match it's glob entries. After
   * the tasks are run, their outputs are added to the set of changed files, in
   * case a task is configured to operate on them.
   *
   * Returns a [BuildResult] combining the results of all task runs.
   */
  Future<BuildResult> _build(Iterable<InputFile> files) {
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
        _logger.info("Rule $rule matches no files.");
        return new Future.value(buildResult);
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
          var newFiles = taskResult.outputs.map((f) =>
              new InputFile(task.name, f, _taskOutDir(task).toString()));
          allFiles.addAll(newFiles);
          // remember this tasks output dir for symlinking
          prevOutDir = taskOutDir;

          return buildResult;
        });
    }).then((buildResult) {
      return _symlinkSources(prevOutDir, outDir).then((_) => buildResult);
    }).catchError((e) {
      _logger.severe("build failed");
    });
  }

  /** Run a [task] on [files]. */
  Future<TaskResult> _runTask(Task task, Iterable<InputFile> files) {
    var taskOutDir = _taskOutDir(task);
    return _createBuildDir(taskOutDir)
        .then((_) {
          _logger.info("Running ${task.name} on $files");
          return task.run(files, basePath, taskOutDir, genDir)
              .catchError((e) {
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
    inDir = inDir == null ? basePath : inDir;
    if (!inDir.isAbsolute) {
      inDir = new Path(Directory.current.path).join(inDir);
    }
    _logger.fine("symlinking sources from $inDir to $outDir");

    return visitDirectory(new Directory.fromPath(inDir), (e) {
      var relativePath = new Path(e.path).relativeTo(inDir);
      _logger.finer("visiting $relativePath");
      if (!isValidInputFile(relativePath.toString())) {
        _logger.finer("  not valid input file");
        return new Future.value(false);
      }

      if (e is File) {
        var linkPath = outDir.join(relativePath);
        var file = new File.fromPath(linkPath);
        if (!file.existsSync()) {
          return new Link.fromPath(linkPath).create(e.path)
              .then((_) => false);
        }
      } else if (e is Directory) {
        _logger.finer("  directory");
        var linkPath = outDir.join(relativePath);
        var dir = new Directory.fromPath(linkPath);

        if (!dir.existsSync()) {
          return new Link.fromPath(linkPath).create(e.path)
              .then((_) => true);
        }
        return new Future.value(true);

      } else if (e is Link) {
        var target = e.targetSync();
        if (target != null) {
          var relativePath = new Path(e.path).relativeTo(inDir);
          var linkPath = outDir.join(relativePath);
          var linkType = FileSystemEntity
              .typeSync(linkPath.toNativePath(), followLinks: false);
          if (linkType == FileSystemEntityType.NOT_FOUND) {
            return new Link.fromPath(linkPath).create(target)
                .then((_) => false)
                .catchError((e) {
                  _logger.severe("error creating link: $e target: $target");
                  return false;
                });
          }
        }
      }
      return new Future.value(false);
    });
  }

  /** Creates the output and gen directories */
  Future _createDirs() => _createDir(buildDir).then((_) =>
      Future.wait([_createBuildDir(outDir), _createDir(genDir)]));

  /** Creates the output directory and adds a packages/ symlink */
  Future _createBuildDir(Path buildDirPath) {
    var dir = new Directory.fromPath(buildDirPath);

    return dir.exists().then((exists) {
      var create = (exists) ? new Future.value(true) : dir.create();
      return create.then((_) {
        // create pub symlink
        var linkPath = buildDirPath.append(PACKAGES);
        var linkType = FileSystemEntity.typeSync(linkPath.toNativePath(),
            followLinks: true);
        if (linkType != FileSystemEntityType.DIRECTORY) {
          if (linkType != FileSystemEntityType.NOT_FOUND) {
            new Link.fromPath(linkPath).deleteSync();
          }
          var targetPath = new File(PACKAGES).fullPathSync();
          return new Link.fromPath(linkPath).create(targetPath);
        } else {
          return new Future.value(null);
        }
      });
    });
  }

  /** Creates the gen directory */
  Future<bool> _createDir(Path buildDirPath) {
    var dir = new Directory.fromPath(buildDirPath);
    return dir.exists().then((exists) =>
        (exists)
            ? new Future.value(true)
            : dir.create().then((_) => true));
  }

  /** Cleans the given directory */
  Future<bool> _cleanDir(Path dirPath) {
    var dir = new Directory.fromPath(dirPath);
    return dir.exists().then((exists) =>
        (exists)
            ? dir.delete(recursive: true).then((_) => true)
            : new Future.value(false));
  }

  Future<Iterable<String>> _getAllFiles() {
    var files = <String>[];
    return visitDirectory(new Directory.fromPath(basePath), (e) {
      var relativePath = new Path(e.path).relativeTo(basePath);
      if (!isValidInputFile(relativePath.toString())) {
        return new Future.value(false);
      }
      if (e is File) {
        files.add(_toString(new Path(e.path).relativeTo(basePath)));
        return new Future.value(false);
      } else {
        return new Future.value(!e.path.endsWith(PACKAGES));
      }
    }).then((_) => files);
  }

  Path _taskOutDir(Task task) => buildDir.append('_${task.name}');
}

String _toString(o) => (o == null) ? null : o.toString();

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
    patterns = files.map((f) {
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

  String toString() => "${task.name} $patterns";
}
