import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

import 'ui/theme.dart';

/// The undo button with Write's rewind dial (`ButtonDragDial` in
/// `syncscribble/touchwidgets.cpp`, set up in `mainwindow.cpp`). A tap undoes
/// one step. A drag turns a dial beside the button: each 1/32 turn clockwise
/// redoes one step, and each 1/32 turn counterclockwise undoes one step.
class UndoDial extends StatefulWidget {
  const UndoDial({
    super.key,
    required this.enabled,
    required this.onStep,
    required this.child,
  });
  final bool enabled;
  // Undoes (-1) or redoes (1) one step and tells whether a step happened.
  final bool Function(int direction) onStep;
  final Widget child;

  @override
  State<UndoDial> createState() => _UndoDialState();
}

class _UndoDialState extends State<UndoDial> {
  static const stepAngle = 2 * math.pi / 32;
  final portal = OverlayPortalController();
  Rect dial = Rect.zero;
  double prevAngle = 0;
  double indAngle = 0;
  int indCount = 0;
  bool moved = false;
  bool focused = false;

  double angle(Offset global) {
    final p = global - dial.center;
    return math.atan2(p.dy, p.dx);
  }

  // Write's onStep: redo while the delta is positive, undo while it is
  // negative; the rest is the delta that no step used.
  int step(int delta) {
    while (delta > 0 && widget.onStep(1)) delta--;
    while (delta < 0 && widget.onStep(-1)) delta++;
    return delta;
  }

  void down(PointerDownEvent event) {
    if (!widget.enabled) return;
    // Write's dial is five button heights square, 130% of the button size
    // away from the button and centered on it. The dial opens on the page
    // side of the rail, to the right.
    final box = context.findRenderObject()! as RenderBox;
    final button = box.localToGlobal(Offset.zero) & box.size;
    final side = 5 * button.height;
    dial = Rect.fromLTWH(
      button.left + 1.3 * button.width,
      button.center.dy - side / 2,
      side,
      side,
    );
    moved = false;
    indCount = 0;
    prevAngle = angle(event.position);
    indAngle = prevAngle;
    portal.show();
    setState(() {});
  }

  void move(PointerMoveEvent event) {
    if (!portal.isShowing) return;
    var delta = angle(event.position) - prevAngle;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    final steps = delta ~/ stepAngle;
    if (steps == 0) return;
    moved = true;
    prevAngle = (prevAngle + steps * stepAngle) % (2 * math.pi);
    final remaining = step(steps);
    setState(() {
      indAngle = prevAngle;
      indCount += steps - remaining;
    });
  }

  void up(PointerEvent event) {
    if (!portal.isShowing) return;
    portal.hide();
    if (!moved && event is PointerUpEvent) step(-1);
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: portal,
    overlayChildBuilder: (context) => Positioned.fromRect(
      rect: dial,
      child: IgnorePointer(
        child: CustomPaint(
          painter: _DialPainter(indAngle, indCount, stepAngle),
        ),
      ),
    ),
    // The button claims its pointer so the rail does not scroll while the
    // dial turns. Tab focuses it and Enter or Space undoes one step.
    child: FocusableActionDetector(
      enabled: widget.enabled,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (value) => setState(() => focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => step(-1),
        ),
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: focused ? Border.all(color: accentText, width: 2) : null,
        ),
        child: RawGestureDetector(
          gestures: {
            EagerGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                  EagerGestureRecognizer.new,
                  (instance) {},
                ),
          },
          child: Listener(
            onPointerDown: down,
            onPointerMove: move,
            onPointerUp: up,
            onPointerCancel: up,
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

// ButtonDragDial::draw: a 100-unit canvas scaled to the dial box, the swept
// sector, and 32 ticks that turn with the dial.
class _DialPainter extends CustomPainter {
  _DialPainter(this.angle, this.count, this.stepAngle);
  final double angle;
  final int count;
  final double stepAngle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.width / 83.3);
    var sweep = (2 * math.pi + count * stepAngle) % (2 * math.pi);
    if (count == 0) sweep = 2 * math.pi;
    if (sweep != 0) {
      const r = 40.0;
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(r * math.cos(angle), r * math.sin(angle))
        ..arcTo(
          Rect.fromCircle(center: Offset.zero, radius: r),
          angle,
          -sweep,
          false,
        )
        ..close();
      canvas.drawPath(path, Paint()..color = selectedFill);
    }
    final tick = Paint()
      ..color = tertiaryLabel
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 32; i++) {
      final a = i * stepAngle - angle;
      canvas.drawLine(
        Offset(39 * math.sin(a), 39 * math.cos(a)),
        Offset(33 * math.sin(a), 33 * math.cos(a)),
        tick,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.angle != angle || old.count != count;
}
