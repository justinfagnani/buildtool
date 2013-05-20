// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library buildtool.launcher_test;

import 'dart:async';
import 'dart:io';
import 'package:buildtool/src/client.dart';
import 'package:buildtool/src/common.dart';
import 'package:buildtool/src/launcher.dart';
import 'package:logging/logging.dart';
import 'package:unittest/mock.dart';
import 'package:unittest/unittest.dart';
import 'utils.dart';

class ClientMock extends Mock implements Client {}

class ProcessMock extends Mock implements Process {
  StreamController<List<int>> _stdoutController;
  Stream<List<int>> stdout;

  ProcessMock() {
    _stdoutController = new StreamController<List<int>>();
    stdout = _stdoutController.stream;
  }
}

main() {
  Logger.root.onRecord.listen((r) =>
      print("${r.loggerName} ${r.level} ${r.message}"));
  Logger.root.level = Level.FINE;

  setUp(() {
    // verify that test data is present
    // TODO(justinfagnani): copy test data to temp directory and run tests there
    checkDirectory('test/data');
    checkDirectory('test/data/packages');
    checkFile('test/data/test.html');
    checkFile('test/data/test.txt');
    checkFile('test/data/.buildlock', exists: false);    
  });

  tearDown(() {
    var lockFile = new File('test/data/$BUILDLOCK_FILE');
    if (lockFile.existsSync()) {
      lockFile.deleteSync();
    }
  });

  test('no lockfile', () {
    var mockClient = new ClientMock();
    var mockProcess = new ProcessMock();
    mockClient.when(callsTo('build')).thenReturn(new Future.value(true));
    int port;

    var launcher = new Launcher(
        baseDir: new Path('data'),
        clientFactory: (p) {
          port = p;
          return mockClient;
        },
        runScript: (exe, args) => new Future.value(mockProcess));

    launcher.run().then(expectAsync1((s) {
      expect(s, true);
      expect(port, 12345);
    }));

    mockProcess._stdoutController.add("port: 12345\n".codeUnits);
  });

  test('lockfile', () {
    var mockClient = new ClientMock();
    mockClient.when(callsTo('build')).thenReturn(new Future.value(true));
    int port;

//    print(new Directory.current().path);
    var lockFile = new File('test/data/$BUILDLOCK_FILE');
    lockFile.writeAsStringSync("54321");

    var launcher = new Launcher(
        baseDir: new Path('test/data'),
        clientFactory: (p) {
          port = p;
          return mockClient;
        },
        runScript: (exe, args) =>
            throw new StateError("runScript should not be called"));

    launcher.run().then(expectAsync1((s) {
      expect(s, true);
      expect(port, 54321);
    }));

  });
}
