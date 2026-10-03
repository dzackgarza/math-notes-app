import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

enum HistoryGesture { twoFingerTap, threeFingerTap, threeFingerSwipeLeft, threeFingerSwipeRight }

// Device preferences stay in the web host. The values are independent of a
// notes folder, so changing folders does not change the editor controls.
class AppPreferences extends ChangeNotifier {
  static const dialChoices = [8, 16, 32, 64];

  int _undoDialSteps = int.parse(
    web.window.localStorage.getItem('undoDialSteps') ?? '32',
  );
  int get undoDialSteps => _undoDialSteps;
  set undoDialSteps(int value) {
    if (!dialChoices.contains(value)) throw ArgumentError.value(value);
    if (_undoDialSteps == value) return;
    web.window.localStorage.setItem('undoDialSteps', '$value');
    _undoDialSteps = value;
    notifyListeners();
  }

  bool _reopenLastNote =
      web.window.localStorage.getItem('reopenLastNote') == 'true';
  bool get reopenLastNote => _reopenLastNote;
  set reopenLastNote(bool value) {
    if (_reopenLastNote == value) return;
    web.window.localStorage.setItem('reopenLastNote', '$value');
    _reopenLastNote = value;
    notifyListeners();
  }

  bool _darkAppearance =
      web.window.localStorage.getItem('appearance') == 'dark';
  bool get darkAppearance => _darkAppearance;
  set darkAppearance(bool value) {
    if (_darkAppearance == value) return;
    web.window.localStorage.setItem('appearance', value ? 'dark' : 'light');
    _darkAppearance = value;
    notifyListeners();
  }

  HistoryGesture _undoGesture = HistoryGesture.values.byName(
    web.window.localStorage.getItem('undoGesture') ?? 'twoFingerTap',
  );
  HistoryGesture get undoGesture => _undoGesture;
  set undoGesture(HistoryGesture value) {
    if (value == _redoGesture) throw ArgumentError.value(value);
    if (_undoGesture == value) return;
    web.window.localStorage.setItem('undoGesture', value.name);
    _undoGesture = value;
    notifyListeners();
  }

  HistoryGesture _redoGesture = HistoryGesture.values.byName(
    web.window.localStorage.getItem('redoGesture') ?? 'threeFingerTap',
  );
  HistoryGesture get redoGesture => _redoGesture;
  set redoGesture(HistoryGesture value) {
    if (value == _undoGesture) throw ArgumentError.value(value);
    if (_redoGesture == value) return;
    web.window.localStorage.setItem('redoGesture', value.name);
    _redoGesture = value;
    notifyListeners();
  }
}
