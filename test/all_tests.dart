library all_tests;

import 'builder_test.dart' as builder_test;
import 'glob_test.dart' as glob_test;
import 'utils_test.dart' as utils_test;

main() {
  builder_test.main();
  glob_test.main();
  utils_test.main();
}
