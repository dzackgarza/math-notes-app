import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

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
  int fingers = 0;
  Duration start = Duration.zero;
  bool valid = false;

  void cancel() => valid = false;

  int add(PointerEvent event) {
    if (event is PointerDownEvent) {
      if (origins.isEmpty) {
        fingers = 0;
        start = event.timeStamp;
        valid = true;
      }
      origins[event.pointer] = event.position;
      if (origins.length > fingers) fingers = origins.length;
      return 0;
    }
    final origin = origins[event.pointer];
    if (origin == null) return 0;
    if ((event.position - origin).distance > kTouchSlop ||
        event is PointerCancelEvent) {
      valid = false;
    }
    if (event is! PointerUpEvent && event is! PointerCancelEvent) return 0;
    origins.remove(event.pointer);
    if (origins.isNotEmpty ||
        !valid ||
        event.timeStamp - start > kLongPressTimeout) {
      return 0;
    }
    return fingers;
  }
}
