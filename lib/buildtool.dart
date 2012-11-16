// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * buildtool is a simple build system for Dart that works well standalone or 
 * with the Dart Editor. buildtool configurations are simple Dart scripts.
 * 
 * ## Usage ##
 * 
 * Call [addTask] with a list of regexs for matching file names and a task to
 * run when files matching the regex change.
 * 
 * Example:
 * 
 *     main() {
 *       addTask([".*\.html"], new WebComponentsTask());
 *       buildWithArgs(new Options().arguments);
 *     }
 * 
 * For convenience, we recommend that developers providing tasks for their
 * tools to also provide a function that helps users register them, so for
 * example a user can simple install a task as follows:
 * 
 *     import 'package:buildtool/web_components.dart';
 *     
 *     main() {
 *       webComponents(files: [".*\.html"]);
 *       buildWithArgs(new Options().arguments);
 *     }
 * 
 * ## Warning ##
 * 
 * This library is extremely new and unfinished. It may change at any time.
 */
library buildtool;

import 'dart:io';
import 'package:args/args.dart';
import 'package:logging/logging.dart';
import 'package:buildtool/glob.dart';

part 'src/builder.dart';
part 'src/symlink.dart';

final Logger _logger = new Logger("buildtool");

Builder builder = new Builder(new Path('out'), new Path('packages/gen'));

/** A runnable build task */
abstract class Task {
  
  /** 
   * Called to run the task.
   * 
   * [files] contains a list of changed paths, not necessarily all files
   * covered by this task in the project [outDir] is where final build
   * artifacts must be written to, [genDir] is where generated files that can
   * be referenced by code should be written to.
   */
  Future<TaskResult> run(List<Path> files, Path outDir, Path genDir);
}

class TaskResult {
  final bool succeeded;
  final List<Path> outputs;
  final List<String> messages;
  TaskResult(this.succeeded, this.outputs, this.messages);
  String toString() => "#<TaskResult succeeded: $succeeded outs: $outputs>";
}

/**
 * Adds a new [Task] to this build which is run when files
 * match against the regex patterns in [files].
 */
void addTask(List<String> files, Task task) => builder.addTask(files, task);

/**
 * Runs the build.
 * 
 * [arguments] is a list of Strings compatible with the command line arguments
 * passed to the build.dart file by the Dart Editor, including:
 *  - --changed: the file has changed since the last build
 *  - --removed: the file was removed since the last build
 *  - clean: remove any build artifacts
 */
Future buildWithArgs(List<String> arguments) {
  var args = _processArgs(arguments);

  var trackDirs = <Directory>[];
  var changedFiles = args["changed"];
  var removedFiles = args["removed"];
  var cleanBuild = args["clean"];
    
  return builder.build(changedFiles, removedFiles, cleanBuild);
}

/** Handle --changed, --removed, --clean and --help command-line args. */
ArgResults _processArgs(List<String> arguments) {
  var parser = new ArgParser()
    ..addOption("changed", help: "the file has changed since the last build",
        allowMultiple: true)
    ..addOption("removed", help: "the file was removed since the last build",
        allowMultiple: true)
    ..addFlag("clean", negatable: false, help: "remove any build artifacts")
    ..addFlag("help", negatable: false, help: "displays this help and exit");
  var args = parser.parse(arguments);
  if (args["help"]) {
    print(parser.getUsage());
    exit(0);
  }
  return args;
}
