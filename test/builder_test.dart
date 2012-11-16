// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library builder_test;

import 'dart:io';
import 'package:unittest/unittest.dart';
import 'package:buildtool/buildtool.dart';
import 'mock_task.dart';

main() {
  var outPath = new Path('test/data/output');
  var genPath =  new Path('test/data/gen');
  // the test task doesn't touch files, so it's ok these don't really exist
  var testPath = new Path('test/data/input/test.html');
  var badPath = new Path('test/data/input/test.txt');
  
  tearDown(() {
    new Directory.fromPath(outPath).deleteSync(recursive: true);
    new Directory.fromPath(genPath).deleteSync(recursive: true);
  });
  
  test('basic', () {
    var task = new MockTask();
    
    var builder = new Builder(outPath, genPath);
    builder.addTask([".*\.html"], task);
    
    builder.build([testPath.toString()], [], true).then(expectAsync1((s) {
      // check output and gen directories
      expect(new Directory.fromPath(outPath).existsSync(), true);
      expect(new Directory.fromPath(genPath).existsSync(), true);
      
      // must convert Paths to Strings for equality
      // TODO(justinfagnani): remove conversion when dartbug.com/6755 is fixed
      expect(task.files.map(_toString), [testPath].map(_toString));
      expect(task.outDir, outPath);
      expect(task.genDir, genPath);
    }));
  });
}

String _toString(o) => o.toString();
