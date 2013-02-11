// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library buildtool.test.utils;

import 'dart:io';

checkDirectory(String dir, { bool exists: true }) {
  if (new Directory(dir).existsSync() != exists) {
    var message = exists
        ? '$dir does not exist'
        : '$dir does exists';
    throw new StateError(message);
  }
}

checkFile(String file, { bool exists: true }) {
  if (new File(file).existsSync() != exists) {
    var message = exists
        ? '$file does not exist'
        : '$file does exists';
    throw new StateError(message);
  }
}
