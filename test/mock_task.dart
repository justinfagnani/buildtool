// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library mock_task;

import 'dart:async';
import 'dart:io';

import 'package:buildtool/task.dart';
import 'package:logging/logging.dart';

var _logger = new Logger("MockTask");

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
    Logger.root.level = Level.FINE;
    _logger.info("files: $files");
    this.files = files;
    this.outDir = outDir;
    this.genDir = genDir;
    var outFiles = [];
    var mappings = {};
    for (var inputFile in files) {
      var outPath = outDir.append(inputFile.path);
      mappings[inputFile.path.toString()] = inputFile.path;

      // copy file to outDir
      var file = new File.fromPath(inputFile.inputPath);
      var contents = file.readAsStringSync();
      var outputFile = new File.fromPath(outPath);
      outputFile.createSync();
      outputFile.writeAsStringSync(contents);

      outFiles.add(outPath.toString());
    }
    _logger.info("MockTask.run finished");
    return new Future.immediate(
        new TaskResult(true, outFiles, mappings, ['message']));
  }
}
