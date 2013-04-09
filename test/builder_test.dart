// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library builder_test;

import 'dart:io';
import 'package:buildtool/src/builder.dart';
import 'package:buildtool/src/common.dart';
import 'package:logging/logging.dart';
import 'package:unittest/unittest.dart';
import 'mock_task.dart';

var _logger = new Logger("builder_test");

main() {
//  Unncomment for verbose output during tests
  Logger.root.onRecord.listen((r) =>
      print("${r.loggerName} ${r.level} ${r.message}"));
  Logger.root.level = Level.FINE;

  var sourcePath = new Path('test/data');
  var buildPath = new Path(BUILD_DIR);
  var outPath =  buildPath.append('out');
  var deployPath =  buildPath.append('deploy');
  var genPath =  new Path('gen');

  tearDown(() {
    _deleteDir(sourcePath.join(buildPath));
    _deleteDir(sourcePath.join(genPath));
  });

  test('addRule duplicate names', () {
    var builder = new Builder(buildPath, genPath, deployPath);
    var task = new MockTask('task');
    builder.addRule('task', task, []);
    expect(() => builder.addRule('task', task, []),
        throwsA(predicate((e) => e is ArgumentError)));
  });

  test('bad dependency', () {
    var builder = new Builder(buildPath, genPath, deployPath);
    var task = new MockTask('task1');
    expect(() => builder.addRule('task1', task, ['task2:*.html']),
        throwsA(predicate((e) => e.message.contains('task2'))));
  });

  test('single task', () {
    var taskOutPath = sourcePath.join(buildPath).append('_mock');
    var file1Path = 'test.html';
    var file2Path = 'test.txt';
    var out1Path = taskOutPath.append(file1Path).toString();
    var out2Path = taskOutPath.append(file2Path).toString();

    var task = new MockTask('mock');
    var builder = new Builder(buildPath, genPath, deployPath,
        basePath: sourcePath);
    builder.addRule('mock', task, ["*.html"]);

    builder.build([file1Path, file2Path], [], clean: false)
        .then(expectAsync1((result) {

          // check output and gen directories were created
          expect(_dirExists(sourcePath.join(buildPath)), true);
          expect(_dirExists(taskOutPath), true);
          expect(_dirExists(sourcePath.join(outPath)), true);
          expect(_dirExists(sourcePath.join(genPath)), true);

          _logger.fine("mappings: ${result.mappings}");
          // check outputs
          expect(result.mappings.length, 1);
          // the input file should map into task out dir
          expect(result.mappings, containsPair(file1Path, out1Path));

          var out1File = new File(out1Path);
          expect(out1File.existsSync(), true);
          // should be a real file in the task output dir
          expect(out1File.fullPathSync(),
              endsWith('data/build_out/_mock/test.html'));

          var out2File = new File(out2Path);
          expect(out2File.existsSync(), true);
          // should be a symlink to the source file, so the full path will
          // be the original, not the location of the symlink
          expect(out2File.fullPathSync(), endsWith('data/test.txt'));

          // check that the mock task only received [file1Path], and not
          // [file2Path] or other files
          expect(task.files.map((f) => f.path), [file1Path]);

          // check task dirs set correctly
          // must convert Paths to Strings for equality
          // TODO(justinfagnani): remove toString when dartbug.com/6755 is fixed
          expect(task.outDir.toString(), taskOutPath.toString());
          // TODO: uncomment this line when we figure out the correct location
//          expect(task.genDir.toString(), genPath.toString());
        }));
  });

  test('independent tasks', () {
    var task1 = new MockTask('task1');
    var task2 = new MockTask('task2');

    var task1OutPath = sourcePath.join(buildPath).append('_task1');
    var task2OutPath = sourcePath.join(buildPath).append('_task2');
    var file1Path = 'test.html';
    var file2Path = 'test.txt';
    var out1Path = task1OutPath.append(file1Path).toString();
    var out2Path = task2OutPath.append(file2Path).toString();

    var builder = new Builder(buildPath, genPath, deployPath,
        basePath: sourcePath);
    builder.addRule('task1', task1, ["*.html"]);
    builder.addRule('task2', task2, ["*.txt"]);

    builder.build([file1Path, file2Path], [], clean: false)
        .then(expectAsync1((BuildResult result) {
          expect(result.mappings, containsPair(file1Path, out1Path));
          expect(result.mappings, containsPair(file2Path, out2Path));
          // TODO: check the links in the out dir
        }));
  });

//  Disabling this test for now, since direct inter task dependencies are not
//  completely defined or implemented yet, but if they were this test might
//  pass as is, so leaving it as a partial spec.
//
//  test('dependent tasks', () {
//    var task1 = new MockTask('task1');
//    var task2 = new MockTask('task2');
//
//    var filePath = 'test.html';
//
//    var builder = new Builder(buildPath, genPath, sourceDirPath: sourcePath);
//    builder.addRule('task1', task1, ["*.html"]);
//    builder.addRule('task2', task2, [task1.out("*.html")]);
//    builder.build([filePath], [], clean:false)
//        .then(expectAsync1((BuildResult result) {
//          // check that task2 gets the file from task1
//          expect(task2.files.length, 1);
//          expect(task2.files[0].dir, 'build_out/_task1');
//        }));
//  });

  test('clean', () {
    // create some trash in the build and gen dirs
    new Directory.fromPath(sourcePath.join(buildPath).append('trash'))
        .createSync(recursive: true);
    new Directory.fromPath(sourcePath.join(genPath).append('trash'))
        .createSync(recursive: true);
    var builder = new Builder(buildPath, genPath, deployPath,
        basePath: sourcePath);
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
    try {
      // this only fails when running multiple tests and may be a bug in dart:io
      dir.deleteSync(recursive: true);
    } on DirectoryIOException catch(e) {
      _logger.severe("Error deleting $path");
    }
  }
}
