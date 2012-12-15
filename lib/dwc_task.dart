// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dwc_task;

import 'dart:io';
import 'package:buildtool/task.dart';
import 'package:buildtool/buildtool.dart';
import 'package:web_ui/dwc.dart' as dwc;

void compileWebComponents({String name, List<String> files}) =>
    addTask(files, new DwcTask());

class DwcTask extends Task {
  
  Future<TaskResult> run(List<Path> files, Path outDir, Path genDir) {
    var futures = <Future<dwc.CompilerResult>>[];
    var outs = [];
    var out = outDir.append('web_components');
    for (var file in files) {
      futures.add(dwc.run(['-o', outDir.toString(), file.toString()]));
    }
    return Futures.wait(futures).transform((_) {
      List<dwc.CompilerResult> results = futures.map((f) => f.value);
      var mappings = new Map<String, String>();
      for (var result in results) {
        for (var output in result.outputs.keys) {
          if (result.outputs[output] != null) {
            mappings[result.outputs[output]] = output;
          }
        }
      }
      return new TaskResult(
          results.every((r) => r.success), 
          _flatMap(results, (result) => result.outputs.keys),
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
