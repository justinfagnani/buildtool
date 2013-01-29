// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dwc_task;

import 'dart:async';
import 'dart:io';
import 'package:buildtool/buildtool.dart';
import 'package:buildtool/task.dart';
import 'package:web_ui/dwc.dart' as dwc;
import 'package:logging/logging.dart';

Logger _logger = new Logger('dwc_task');

DwcTask compileWebComponents({String name: "web_ui", List<String> files}) =>
    addRule(name, new DwcTask(name), files);

class DwcTask extends Task {

  DwcTask(String name) : super(name);

  Future<TaskResult> run(List<InputFile> files, Path outDir, Path genDir) {

    var futures = <Future<dwc.CompilerResult>>[];

    for (var file in files) {
      var fileOutDir = outDir.join(file.inputPath).directoryPath;
      var args = ['--out', outDir.toString()];
      var basedir = (file.dir != null) ? file.dir : '.';
      args.addAll(['--basedir', basedir]);
      args.add(file.inputPath.toNativePath());
      futures.add(dwc.run(args));
    }
    return Future.wait(futures).then((List<dwc.CompilerResult> results) {
      var mappings = new Map<String, String>();
      var outputs = <String>[];

      for (var result in results) {
        for (var output in result.outputs.keys) {
          var outputPath = output.substring(outDir.toString().length + 1);
          outputs.add(outputPath);
          if (result.outputs[output] != null) {
            var sourcePath = result.outputs[output];
            mappings[sourcePath] = outputPath;
          }
        }
      }
      return new TaskResult(
          results.every((r) => r.success),
          outputs,
          mappings,
          _flatMap(results, (result) => result.messages));
    });
  }
}

// TODO(justinfagnani): replace with Iterable.expand() when it's available
List _flatMap(List l, f) {
  var result = [];
  l.forEach((i) => result.addAll(f(i)));
  return result;
}
