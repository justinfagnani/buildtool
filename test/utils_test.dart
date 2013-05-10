// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library utils_test;

import 'dart:async';
import 'dart:isolate';
import 'package:buildtool/src/util/async.dart';
import 'package:unittest/unittest.dart';

main() {
  test('reduceAsync', () {
    var data = [1, 2, 3];

    // define an async function, this sums the inputs
    Future<int> sum(int a, int b) => new Future.value(a + b);

    reduceAsync(data, 0, expectAsync2(sum, count: data.length)).then((result) {
      expect(result, 6);
    });
  });
}
