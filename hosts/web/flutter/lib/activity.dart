import 'dart:async';

import 'package:flutter/foundation.dart';

import 'errors.dart';

// The one path for user actions: each action counts as work in progress while
// it runs, and each failure shows through showError.
class Activity extends ChangeNotifier {
  // The number of actions in progress; the navigation bar shows a spinner.
  int tasks = 0;
  final Set<Future<void>> _pending = {};
  bool _switchingFolder = false;

  Future<void> run(Future<void> Function() action) {
    if (_switchingFolder) {
      showError(StateError('Wait for the notes folder switch to finish.'));
      return Future.value();
    }
    final completed = Completer<void>();
    _pending.add(completed.future);
    return _run(action).whenComplete(() {
      _pending.remove(completed.future);
      completed.complete();
    });
  }

  // Picking must begin in the button's user gesture. The selected folder
  // becomes current only after admitted actions (including their UI results)
  // have finished, so none can resume against a different notes folder.
  Future<void> switchFolder<T>(
    Future<T> Function() pick,
    Future<void> Function(T) connect,
  ) {
    if (_switchingFolder) {
      showError(StateError('Wait for the notes folder switch to finish.'));
      return Future.value();
    }
    _switchingFolder = true;
    final pending = Future.wait(_pending.toList());
    return _run(() async {
      final chosen = await pick();
      await pending;
      await connect(chosen);
    }).whenComplete(() => _switchingFolder = false);
  }

  Future<void> _run(Future<void> Function() action) async {
    tasks++;
    notifyListeners();
    try {
      await action();
    } catch (error, stack) {
      showError(error, stack);
    } finally {
      tasks--;
      notifyListeners();
    }
  }
}

// A step that neither finishes nor throws is a failure: it fails with a
// message that names the step.
Future<T> deadline<T>(String step, Duration limit, Future<T> future) =>
    future.timeout(
      limit,
      onTimeout: () => throw TimeoutException(
        '$step did not finish in ${limit.inSeconds} s.',
      ),
    );
