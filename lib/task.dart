// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library task;

import 'dart:async';
import 'dart:io';

/** A runnable build task */
abstract class Task {
  /** */
  final String name;

  Task(String this.name);

  /**
   * Called to run the task.
   *
   * [files] contains a list of changed paths, not necessarily all files
   * covered by this task in the project. [outDir] is where final build
   * artifacts must be written to, [genDir] is where generated files that can
   * be referenced by code should be written to.
   */
  Future<TaskResult> run(List<InputFile> files, Path outDir, Path genDir);

  /** Returns a file pattern for matching output of this task using [pattern] */
  String out(String pattern) => '$name:$pattern';
}

/** Metadata about an input file passed to a task. */
class InputFile {

  /**
   * The name of the task that generated the file, or '_source' if the file is
   * from the original source tree.
   */
  final String task;

  /**
   * Either `null` indicating an original source file, or the build directory
   * containing the file. This will usually be 'build/_foo' for a file produced
   * by a task named 'foo'.
   */
  final String dir;

  /** The path of the file relative to the project. */
  final String path;

  InputFile(this.task, this.path, this.dir) {
    assert(path != null);
    assert(dir != null);
  }

  /** The location of the file on disk. */
  Path get inputPath => new Path(dir).join(new Path(path));

  String get matchString => '$task:$path';

  String toString() => matchString;
}

/**
 * Information about the task run.
 */
class TaskResult {
  final bool succeeded;
  final List<String> outputs;

  /** Mapping of inputs to outputs. */
  final Map<String, String> mappings;
  final List<String> messages;

  TaskResult(this.succeeded, this.outputs, this.mappings, this.messages);

  String toString() => "#<TaskResult succeeded: $succeeded outs: $outputs> "
      "mappings: $mappings";
}
