// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library utils;

import 'dart:io';
import 'dart:uri';
export 'package:web_ui/src/utils.dart' show FutureGroup;
import 'package:logging/logging.dart';

Future<String> readStreamAsString(InputStream stream) {
  var completer = new Completer();
  var sb = new StringBuffer();
  var sis = new StringInputStream(stream);
  sis
  ..onData = () {
    sb.add(sis.read());
  }
  ..onClosed = () {
    completer.complete(sb.toString());
  }
  ..onError = completer.completeException;
  return completer.future;
}

Future<String> readFileAsString(String filename) =>
    readStreamAsString(new File(filename).openInputStream());

String uriToNativePath(Uri uri) {
  if (uri.scheme != 'file') {
    throw new ArgumentError(uri);
  }
  return new Path(uri.path).toNativePath();
}

void printLogRecord(LogRecord r) {
  print("${r.loggerName} ${r.level} ${r.message}");
}

/** 
 * Merges [maps] by adding the key/value pairs from each map to a new map.
 * Values in the laters maps overwrite values in the earlier maps.
 */
Map mergeMaps(List<Map> maps) {
  var result = new Map();
  for (var map in maps) {
    for (var key in map.keys) {
      result[key] = map[key];
    }
  }
  return result;
}
