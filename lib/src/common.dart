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


bool isValidInputFile(String f) => 
    !(f.startsWith(BUILD_DIR) || f == BUILDLOG_FILE || f == BUILDLOCK_FILE);
