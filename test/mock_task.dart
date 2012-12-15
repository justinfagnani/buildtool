// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library mock_task;

import 'dart:io';
import 'package:buildtool/task.dart';

class MockTask extends Task {
  List<InputFile> files;
  Path outDir;
  Path genDir;
  
  MockTask(String name) : super(name);
  
  /** 
   * Returns a [BuildResult] with:
   * * `outputs` are input files paths
   * * `mappings` with all inputs mapped to their output
   * * A single message of `'message'`
   */
  Future<TaskResult> run(List<InputFile> files, Path outDir, Path genDir) {
    print("files: $files");
    this.files = files;
    this.outDir = outDir;
    this.genDir = genDir;
    var outFiles = files.map((f) => f.path);
    var mappings = {};
    files.forEach((f) => mappings[f.inputPath.toString()] = f.path); 
    return new Future.immediate(
        new TaskResult(true, outFiles, mappings, ['message']));
  }
}
