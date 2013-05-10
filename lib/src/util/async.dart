// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library buildtool.util.async;

import 'dart:async';

/**
 * Similar to [Iterable.reduce], except that [combine] is an async function
 * that returns a [Future].
 *
 * Reduce a collection to a single value by iteratively combining each element
 * of the collection with an existing value using the provided function. Use
 * initialValue as the initial value, and the function combine to create a new
 * value from the previous one and an element.
 */
Future reduceAsync(Iterable iterable, initialValue, combine(previous, element))
    => _reduceAsync(iterable.iterator, initialValue, combine);

Future _reduceAsync(Iterator iterator, currentValue,
                    combine(previous, element)) {
  if (iterator.moveNext()) {
    return combine(currentValue, iterator.current).then((result) =>
        _reduceAsync(iterator, result, combine));
  }
  return new Future.value(currentValue);
}
