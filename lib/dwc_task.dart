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

  Future<TaskResult> run(List<InputFile> files, Path baseDir, Path outDir,
      Path genDir) {
    var futures = <Future<dwc.CompilerResult>>[];
    
    var mappings = <String, String>{};
    var outputs = <String>[];
    var dependencies = <String, List<String>>{};
    var messages = <String>[];
    var success = true;

    for (var file in files) {
      var fileOutDir = outDir.append(file.path).directoryPath;
      var args = ['--out', outDir.toString()];
//      var basedir = (file.dir != null) ? file.dir : '.';
      print("baseDir: $baseDir");
      print("outDir: $outDir");
      args.addAll(['--basedir', baseDir.toString()]);
      args.add(file.inputPath.toNativePath());

      futures.add(dwc.run(args).then((dwc.CompilerResult result) {
        success = success || result.success;        
        for (var output in result.outputs.keys) {
          var outputPath = output.substring(outDir.toString().length + 1);
          outputs.add(outputPath);
          if (result.outputs[output] != null) {
            var sourcePath = result.outputs[output];
            mappings[sourcePath] = outputPath;
          }
        }
        
        dependencies.putIfAbsent(file.path, () => []);
        for (var input in result.inputs) {
          dependencies[file.path].add(input);
        }
        messages.addAll(result.messages);
      }));
    }
    return Future.wait(futures).then((_) =>
        new TaskResult(
          success,
          outputs,
          mappings,
          dependencies,
          messages));
  }
}

// TODO(justinfagnani): replace with Iterable.expand() when it's available
List _flatMap(List l, f) {
  var result = [];
  l.forEach((i) => result.addAll(f(i)));
  return result;
}
