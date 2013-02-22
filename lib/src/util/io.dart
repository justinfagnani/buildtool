// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library buildtool.util.io;

import 'dart:async';
import 'dart:io';
import 'dart:uri';

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
  ..onError = completer.completeError;
  return completer.future;
}

Future<String> readFileAsString(String filename) =>
    new File(filename).readAsString();

String uriToNativePath(Uri uri) {
  if (uri.scheme != 'file') {
    throw new ArgumentError(uri);
  }
  return new Path(uri.path).toNativePath();
}
