// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library all_tests;

import 'builder_test.dart' as builder_test;
import 'client_test.dart' as client_test;
import 'glob_test.dart' as glob_test;
import 'list_directory_test.dart' as list_directory_test;
import 'utils_test.dart' as utils_test;

main() {
  builder_test.main();
  client_test.main();
  glob_test.main();
  list_directory_test.main();
  utils_test.main();
}
