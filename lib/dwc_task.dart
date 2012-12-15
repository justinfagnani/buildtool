// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dwc_task;

import 'dart:io';
import 'package:buildtool/buildtool.dart';
import 'package:buildtool/task.dart';
import 'package:web_ui/dwc.dart' as dwc;
import 'package:logging/logging.dart';

Logger _logger = new Logger('dwc_task');

DwcTask compileWebComponents({String name: "web_ui", List<String> files}) =>
    addTask(files, new DwcTask(name));

class DwcTask extends Task {
  
  DwcTask(String name) : super(name);
  
  Future<TaskResult> run(List<InputFile> files, Path outDir, Path genDir) {
    
    var futures = <Future<dwc.CompilerResult>>[];
    
    for (var file in files) {
      var fileOutDir = outDir.join(file.inputPath).directoryPath;
      var args = ['-o', fileOutDir.toString(), file.inputPath.toNativePath()];
      futures.add(dwc.run(args));
    }
    return Futures.wait(futures).transform((List<dwc.CompilerResult> results) {
      var mappings = new Map<String, String>();
      var outputs = <String>[];
      
      for (var result in results) {
        for (var output in result.outputs.keys) {
          var outputPath = output.substring(outDir.toString().length + 1);
          outputs.add(outputPath);
          if (result.outputs[output] != null) {
            var sourcePath = result.outputs[output];
            mappings[sourcePath] = outputPath;
            _logger.fine("adding mapping: $sourcePath = $outputPath");
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
