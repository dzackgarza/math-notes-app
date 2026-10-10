import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:overlay_support/overlay_support.dart';

import 'theme.dart';

// A card at the top or bottom of the window that fades in. With `closeAfter`
// it closes that long after the pointer last left it; without, it stays until
// it is dismissed. overlay_support removes the card once its closing
// animation has ended.
OverlaySupportEntry showToast({
  required Alignment alignment,
  Duration? closeAfter,
  required Widget child,
}) {
  late final OverlaySupportEntry toast;
  Timer? closing;
  void close() {
    if (closeAfter != null) closing = Timer(closeAfter, toast.dismiss);
  }

  toast = showOverlay(
    (context, progress) => SafeArea(
      child: Align(
        alignment: alignment,
        child: Opacity(
          opacity: progress,
          child: MouseRegion(
            onEnter: (_) => closing?.cancel(),
            onExit: (_) => close(),
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.only(left: 16),
              decoration: BoxDecoration(
                color: surface2,
                borderRadius: BorderRadius.circular(12),
                boxShadow: floatingShadow,
              ),
              child: child,
            ),
          ),
        ),
      ),
    ),
    duration: Duration.zero,
  );
  close();
  toast.dismissed.whenComplete(() => closing?.cancel());
  return toast;
}
