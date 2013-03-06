// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library buildtool.util.io;

import 'dart:async';
import 'dart:io';
import 'dart:uri';
import 'package:buildtool/src/symlink.dart';

String uriToNativePath(Uri uri) {
  if (uri.scheme != 'file') {
    throw new ArgumentError(uri);
  }
  return new Path(uri.path).toNativePath();
}

Future<String> byteStreamToString(Stream<List<int>> stream) =>
    stream.transform(new StringDecoder()).toList().then((l) => l.join(''));
