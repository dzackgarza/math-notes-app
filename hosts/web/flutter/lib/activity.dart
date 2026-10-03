import 'dart:async';

import 'package:flutter/foundation.dart';

import 'errors.dart';

// The one path for user actions: each action counts as work in progress while
// it runs, and each failure shows through showError.
class Activity extends ChangeNotifier {
  // The number of actions in progress; the navigation bar shows a spinner.
  int tasks = 0;

  Future<void> run(Future<void> Function() action) async {
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
