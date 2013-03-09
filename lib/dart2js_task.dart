// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart2js;

import 'dart:async';
import 'dart:io';
import 'dart:uri';
import 'package:buildtool/buildtool.dart';
import 'package:buildtool/task.dart';
import 'package:buildtool/src/util/future_group.dart';
import 'package:logging/logging.dart';

Logger get _logger => new Logger('dart2js');

/** Adds a dart2js task to the build configuration. */
Dart2JSTask dart2js({String name: "dart2js", List<String> files}) =>
    addRule(name, new Dart2JSTask(name), files);

Path get _dart2jsPath => new Path(new Options().executable)
    .directoryPath.append('dart2js');

/** Runs dart2js on the input files. */
class Dart2JSTask extends Task {

  Dart2JSTask(String name) : super(name);

  Future<TaskResult> run(List<InputFile> files, Path baseDir, Path outDir,
      Path genDir) {
    _logger.info("dart2js task starting. files: $files");
    var futureGroup = new FutureGroup<ProcessResult>();
    for (var file in files) {
      var outPath = outDir.append('${file.path}.js');
      var outFileDir = outPath.directoryPath;

      new Directory.fromPath(outFileDir).createSync(recursive: true);

      var options = new ProcessOptions()
        ..workingDirectory = new Directory.current().path;
      var args = ['--out=$outPath', '--verbose', file.inputPath.toNativePath()];

      _logger.fine("running $_dart2jsPath args: $args");
      futureGroup.add(Process.run(_dart2jsPath.toNativePath(), args, options)
         .catchError ((e) {
            _logger.severe("error: $e");
            throw e;
          })
        .then((ProcessResult result) {
          _logger.fine("dart2js exitCode: ${result.exitCode}");
          return result;
        }));
    }
    return futureGroup.future.then((values) {
      _logger.info("dartjs tasks complete");
      var messages = [];
      var success = values.every((v) => v.exitCode == 0);
      for (var r in values) {
        messages.add(r.stdout);
        messages.add(r.stderr);
      }
      return new TaskResult(success, [], {}, {}, messages);
    });
  }
}
