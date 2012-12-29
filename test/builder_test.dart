// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library builder_test;

import 'dart:io';
import 'package:buildtool/src/builder.dart';
import 'package:buildtool/src/utils.dart';
import 'package:logging/logging.dart';
import 'package:unittest/unittest.dart';
import 'mock_task.dart';

main() {
  Logger.root.on.record.add(printLogRecord);
  Logger.root.level = Level.FINE;
  
  var buildPath = new Path('test/data/build');
  var taskOutPath = new Path('test/data/build/_mock');
  var genPath =  new Path('test/data/gen');
  // the test task doesn't touch files, so it's ok these don't really exist
  var testPath = 'test/data/input/test.html';
  var badPath = 'test/data/input/test.txt';
  
  tearDown(() {
    _deleteDir(buildPath);
    _deleteDir(genPath);
  });
  
  test('basic', () {
    var task = new MockTask('mock');
    var builder = new Builder(buildPath, genPath);
    builder.addRule('mock', task, ["**/*.html"]);
    
    builder.build([testPath, badPath], [], true)
        .then(expectAsync1((result) {
          
          // check output and gen directories were created
          expect(_dirExists(buildPath), true);
          expect(_dirExists(buildPath.append('_mock')), true);
          expect(_dirExists(genPath), true);
          
          // check outputs
          expect(result.mappings.length, 1);
          expect(result.mappings[testPath], testPath);
          
          expect(task.files.map((f) => f.path), [testPath]);
          // must convert Paths to Strings for equality
          // TODO(justinfagnani): remove conversion when dartbug.com/6755 is 
          // fixed
          expect(task.outDir.toString(), taskOutPath.toString());
          expect(task.genDir.toString(), genPath.toString());
        }));
  });
  
// TODO(justinfagnani): finish this test
//  test('dependent tasks', () {
//    var task1 = new MockTask('mock');
//    var builder = new Builder(buildPath, genPath);
//    builder.addTask(["**/*.html"], task1);
//    builder.addTask([task1.outputs["**/*.html"]], task1);
//  });
}

bool _dirExists(Path path) => new Directory.fromPath(path).existsSync();

_deleteDir(Path path) {
  var dir = new Directory.fromPath(path);
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);    
  }
}
