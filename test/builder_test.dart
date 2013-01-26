// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library builder_test;

import 'dart:io';
import 'package:logging/logging.dart';
import 'package:unittest/unittest.dart';

import 'package:buildtool/src/builder.dart';
import 'package:buildtool/src/common.dart';
import 'package:buildtool/src/utils.dart';
import 'mock_task.dart';

var _logger = new Logger("builder_test");

main() {
  Logger.root.on.record.add(printLogRecord);
  Logger.root.level = Level.FINE;

  var sourcePath = new Path('test/data');
  var buildPath = sourcePath.append(BUILD_DIR);
  var genPath =  sourcePath.append('gen');

  tearDown(() {
    _deleteDir(buildPath);
    _deleteDir(genPath);
  });

  test('addRule duplicate names', () {
    var builder = new Builder(buildPath, genPath);
    var task = new MockTask('task');
    builder.addRule('task', task, []);
    try {
      builder.addRule('task', task, []);
      fail('exected exception on duplicate names');
    } on ArgumentError catch (e) {
      // pass
    }
  });

  test('bad dependency', () {
    var builder = new Builder(buildPath, genPath);
    var task = new MockTask('task1');
    try {
      builder.addRule('task1', task, ['task2:*.html']);
      fail('exected exception unknown task');
    } on ArgumentError catch (e) {
      expect(e.message, stringContainsInOrder(['task2']));
    }
  });

  test('single task', () {
    var taskOutPath = buildPath.append('_mock');
    var testPath = 'test.html';
    var outPath = taskOutPath.append(testPath).toString();
    var badPath = 'test.txt';

    var task = new MockTask('mock');
    var builder = new Builder(buildPath, genPath, sourceDirPath: sourcePath);
    builder.addRule('mock', task, ["*.html"]);

    builder.build([testPath, badPath], [], clean: false)
        .then(expectAsync1((result) {

          // check output and gen directories were created
          expect(_dirExists(buildPath), true);
          expect(_dirExists(taskOutPath), true);
          expect(_dirExists(genPath), true);

          _logger.fine("mappings: ${result.mappings}");
          // check outputs
          expect(result.mappings.length, 1);
          // the input file should map into task out dir
          expect(result.mappings, containsPair(testPath, outPath));

          // check that the mock task only received [testPath], and not
          // [badPath] or other files
          expect(task.files.mappedBy((f) => f.path), orderedEquals([testPath]));

          // check task dirs set correctly
          // must convert Paths to Strings for equality
          // TODO(justinfagnani): remove toString when dartbug.com/6755 is fixed
          expect(task.outDir.toString(), taskOutPath.toString());
          expect(task.genDir.toString(), genPath.toString());
        }));
  });

  test('independent tasks', () {
    var task1 = new MockTask('task1');
    var task2 = new MockTask('task2');

    var task1OutPath = buildPath.append('_task1');
    var task2OutPath = buildPath.append('_task2');
    var file1Path = 'test.html';
    var file2Path = 'test.txt';
    var out1Path = task1OutPath.append(file1Path).toString();
    var out2Path = task2OutPath.append(file2Path).toString();

    var builder = new Builder(buildPath, genPath, sourceDirPath: sourcePath);
    builder.addRule('task1', task1, ["*.html"]);
    builder.addRule('task2', task2, ["*.txt"]);

    builder.build([file1Path, file2Path], [], clean: false)
        .then(expectAsync1((BuildResult result) {
          expect(result.mappings, containsPair(file1Path, out1Path));
          expect(result.mappings, containsPair(file2Path, out2Path));
          // TODO: check the links in the out dir
        }));
  });

// TODO(justinfagnani): finish this test
//  test('dependent tasks', () {
//    var task1 = new MockTask('task1');
//    var task2 = new MockTask('task2');
//    var builder = new Builder(buildPath, genPath);
//    builder.addRule('task1', task1, ["*.html"]);
//    builder.addRule('task2', task2, [task1.out("*.txt")]);
//
//  });

  solo_test('clean', () {
    // create some trash in the build and gen dirs
    new Directory.fromPath(buildPath.append('trash'))
        .createSync(recursive: true);
    new Directory.fromPath(genPath.append('trash'))
        .createSync(recursive: true);
    var builder = new Builder(buildPath, genPath);
    builder.build(['a.html'], [], clean: true).then(expectAsync1((result) {
      expect(false,
          new Directory.fromPath(buildPath.append('trash')).existsSync());
      expect(false,
          new Directory.fromPath(genPath.append('trash')).existsSync());
    }));
  });
}

bool _dirExists(Path path) => new Directory.fromPath(path).existsSync();

_deleteDir(Path path) {
  var dir = new Directory.fromPath(path);
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
}
