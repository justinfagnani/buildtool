// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library task;

import 'dart:io';

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