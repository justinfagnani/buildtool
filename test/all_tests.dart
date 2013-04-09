// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library all_tests;

import 'builder_test.dart' as builder_test;
import 'client_test.dart' as client_test;
import 'glob_test.dart' as glob_test;
import 'io_test.dart' as io_test;
import 'launcher_test.dart' as launcher_test;
import 'utils_test.dart' as utils_test;

main() {
  builder_test.main();
  client_test.main();
  glob_test.main();
  io_test.main();
  launcher_test.main();
  utils_test.main();
}
