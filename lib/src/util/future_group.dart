// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library future_group;

import 'dart:async';

/** A future that waits until all added [Future]s complete. */
// TODO(sigmund): this should be part of the futures/core libraries.
class FutureGroup<E> {
  const _FINISHED = -1;

  int _count = 0;
  int _pending = 0;
  Future<E> _failedTask;
  final Completer<List<E>> _completer = new Completer<List<E>>();
  final List<E> _values = <E>[];

  /** Gets the task that failed, if any. */
  Future<E> get failedTask => _failedTask;

  /**
   * Wait for [task] to complete.
   *
   * If this group has already been marked as completed, you'll get a exception.
   *
   * If this group has a [failedTask], new tasks will be ignored, because the
   * error has already been signaled.
   */
  void add(Future<E> task) {
    if (_failedTask != null) return;
    if (_pending == _FINISHED) throw new StateError("Future already completed");

    var index = _count;
    _count++;
    _pending++;
    _values.add(null);
    task.then((E value) {
      if (_failedTask != null) return;
      _values[index] = value;
      _pending--;
      if (_pending == 0) {
        _pending = _FINISHED;
        _completer.complete(_values);
      }
    }, onError: (e) {
      if (_failedTask != null) return;
      _failedTask = task;
      _completer.completeError(e.error, e.stackTrace);
    });
  }

  /**
   * A Future that complets with a List of the values from all the added
   * Futures, when they have all completed.
   */
  Future<List<E>> get future => _completer.future;
}
