library common;

import 'dart:io';

final String BUILD_URL = '/build';
final String CLOSE_URL = '/close';
final String STATUS_URL = '/status';
final String BUILDLOG_FILE = '.buildlog';
final String BUILDLOCK_FILE = '.buildlock';

final ContentType JSON_TYPE = new ContentType('application', 'json');
