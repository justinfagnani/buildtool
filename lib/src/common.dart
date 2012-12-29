library common;

import 'dart:io';

final String BUILD_URL = '/build';
final String CLOSE_URL = '/close';
final String STATUS_URL = '/status';
final String BUILDLOG_FILE = '.buildlog';
final String BUILDLOCK_FILE = '.buildlock';
final String BUILD_DIR = 'build_out';
final String OUT_DIR = 'out';
final String SOURCE_PREFIX = '_source';

final ContentType JSON_TYPE = new ContentType('application', 'json');

final List<String> EXCLUDED_FILES = [
  BUILDLOG_FILE,
  BUILDLOCK_FILE,
  'pubspec.yaml',
  'pubspec.lock',
  'build.dart',
  '_build_server.dart',
];

final List<String> EXCLUDED_DIRS = [
  'packages',
  '.git',
];

bool isValidInputFile(String f) => 
    !(f.startsWith(BUILD_DIR) || EXCLUDED_FILES.contains(f));
