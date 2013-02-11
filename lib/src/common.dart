// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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
const String GEN_DIR = 'packages/gen';
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
  '.svn',
];

// TODO(justinfagnani): possibly exclude all hidden files
bool isValidInputFile(String f) =>
    !(EXCLUDED_DIRS.any((d) => f.startsWith(d)) || EXCLUDED_FILES.contains(f));
