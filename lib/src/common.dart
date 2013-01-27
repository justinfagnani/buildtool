library common;

import 'dart:io';

// build server end-points
const String BUILD_URL = '/build';
const String CLOSE_URL = '/close';
const String STATUS_URL = '/status';

// file names
const String LOG_FILE = '.buildtool_log';
const String BUILDLOG_FILE = '.buildlog';
const String BUILDLOCK_FILE = '.buildlock';
const String BUILD_DIR = 'build_out';
const String OUT_DIR = 'out';
const String PACKAGES = 'packages';

const String SOURCE_PREFIX = '_source';

final ContentType JSON_TYPE = new ContentType('application', 'json');

final List<String> EXCLUDED_FILES = [
  LOG_FILE,
  BUILDLOG_FILE,
  BUILDLOCK_FILE,
  'pubspec.yaml',
  'pubspec.lock',
  'build.dart',
  '_build_server.dart',
];

final List<String> EXCLUDED_DIRS = [
  BUILD_DIR,
  PACKAGES,
  '.git',
];

bool isValidInputFile(String f) =>
    !(EXCLUDED_DIRS.any((d) => f.startsWith(d)) || EXCLUDED_FILES.contains(f));
