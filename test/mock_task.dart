// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library mock_task;

import 'dart:io';
import 'package:buildtool/task.dart';

class MockTask implements Task {
  List<Path> files;
  Path outDir;
  Path genDir;
  
  Future<TaskResult> run(List<Path> files, Path outDir, Path genDir) {
    print("files: $files");
    this.files = files;
    this.outDir = outDir;
    this.genDir = genDir;
    return new Future.immediate(new TaskResult(true, [], {}, []));
  }
}
