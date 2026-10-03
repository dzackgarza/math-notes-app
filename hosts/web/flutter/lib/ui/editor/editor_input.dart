import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../data/app_preferences.dart';

enum PageGesture { doubleTap, twoFingerTap, threeFingerTap, threeFingerSwipeLeft, threeFingerSwipeRight }

/// The page transform of an InteractiveViewer that the mouse wheel does not
/// scale. InteractiveViewer scales on each PointerScrollEvent and has no
/// parameter for it, while the scroll view under it scrolls on the same
/// event. The editor sets [held] while such an event passes the viewer, so
/// the wheel scrolls only. Ctrl with the wheel arrives as a
/// PointerScaleEvent on web and zooms. The rule is that of Saber's
/// InteractiveViewer fork (`_receivedPointerSignal` in
/// lib/components/canvas/interactive_canvas.dart).
class PageTransform extends TransformationController {
  bool held = false;

  @override
  set value(Matrix4 next) {
    if (!held) super.value = next;
  }
}

class SelectionTransfer {
  const SelectionTransfer(this.read);
  final FutureOr<String> Function() read;
}

/// Claims each touch that lands during a pen stroke, so a resting palm
/// neither pans nor zooms the page.
class PalmRejection extends EagerGestureRecognizer {
  PalmRejection(this.stroking)
    : super(supportedDevices: {PointerDeviceKind.touch});
  final bool Function() stroking;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      stroking() && super.isPointerAllowed(event);
}

/// Recognizes a tap of several fingers with UIKit-style tap limits.
class FingerTap {
  final origins = <int, Offset>{};
  final displacements = <Offset>[];
  int fingers = 0;
  Duration start = Duration.zero;
  bool valid = false;
  Duration? previousTap;
  Offset? previousPosition;

  void cancel() => valid = false;

  PageGesture? add(PointerEvent event) {
    if (event is PointerDownEvent) {
      if (origins.isEmpty) {
        fingers = 0;
        start = event.timeStamp;
        valid = true;
        displacements.clear();
      }
      origins[event.pointer] = event.position;
      if (origins.length > fingers) fingers = origins.length;
      return null;
    }
    final origin = origins[event.pointer];
    if (origin == null) return null;
    if (event is PointerUpEvent) displacements.add(event.position - origin);
    if ((event.position - origin).distance > kTouchSlop ||
        event is PointerCancelEvent) {
      valid = false;
    }
    if (event is! PointerUpEvent && event is! PointerCancelEvent) return null;
    origins.remove(event.pointer);
    if (origins.isNotEmpty) return null;
    final elapsed = event.timeStamp - start;
    if (fingers == 3 && elapsed < const Duration(milliseconds: 600) &&
        displacements.length == 3) {
      if (displacements.every((delta) => delta.dx < -48 && delta.dy.abs() < delta.dx.abs() / 2)) {
        return PageGesture.threeFingerSwipeLeft;
      }
      if (displacements.every((delta) => delta.dx > 48 && delta.dy.abs() < delta.dx.abs() / 2)) {
        return PageGesture.threeFingerSwipeRight;
      }
    }
    if (!valid || elapsed > kLongPressTimeout) return null;
    if (fingers == 2) return PageGesture.twoFingerTap;
    if (fingers == 3) return PageGesture.threeFingerTap;
    if (fingers != 1) return null;
    final first = previousTap;
    final position = previousPosition;
    previousTap = event.timeStamp;
    previousPosition = event.position;
    if (first != null && position != null &&
        event.timeStamp - first < kDoubleTapTimeout &&
        (position - event.position).distance < kDoubleTapSlop) {
      previousTap = null;
      previousPosition = null;
      return PageGesture.doubleTap;
    }
    return null;
  }
}
