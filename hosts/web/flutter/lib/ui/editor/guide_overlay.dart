part of 'editor_screen.dart';

extension _GuideOverlay on _EditorScreenState {
  Widget guideOverlay() {
    final center = guideCenter ?? Offset(width / 2, height / 2);
    final rotate = Offset(
      center.dx + 168 * math.cos(guideAngle),
      center.dy + 168 * math.sin(guideAngle),
    );
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GuidePainter(guideKind, center, guideAngle, accent),
              ),
            ),
          ),
          Positioned(
            left: center.dx - 20,
            top: center.dy - 20,
            child: Semantics(
              label: 'Move ruler',
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  setState(() => guideCenter = (guideCenter ?? center) + details.delta);
                  updateView();
                },
                child: const _GuideHandle(LucideIcons.move),
              ),
            ),
          ),
          Positioned(
            left: rotate.dx - 18,
            top: rotate.dy - 18,
            child: Semantics(
              label: 'Rotate ruler',
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  final next = details.localPosition + rotate - const Offset(18, 18);
                  setState(() => guideAngle = math.atan2(next.dy - center.dy, next.dx - center.dx));
                  updateView();
                },
                child: const _GuideHandle(LucideIcons.rotateCw),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideHandle extends StatelessWidget {
  const _GuideHandle(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: surface2,
        shape: BoxShape.circle,
        border: Border.all(color: accent, width: 1.5),
        boxShadow: floatingShadow,
      ),
      child: Icon(icon, size: 18, color: accent),
    ),
  );
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter(this.kind, this.center, this.angle, this.color);
  final int kind;
  final Offset center;
  final double angle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final path = Path();
    for (var x = -190; x <= 190; x += 5) {
      final y = kind == 2 ? -55 + 50 * math.pow((x - 30) / 220, 2) : 0;
      if (x == -190) {
        path.moveTo(x.toDouble(), y.toDouble());
      } else {
        path.lineTo(x.toDouble(), y.toDouble());
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = surface2.withValues(alpha: 0.9)
        ..strokeWidth = 9
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    if (kind == 1) {
      final ticks = Paint()
        ..color = color.withValues(alpha: 0.7)
        ..strokeWidth = 1;
      for (var x = -180; x <= 180; x += 20) {
        if (x.abs() < 25 || (x - 168).abs() < 25) continue;
        canvas.drawLine(Offset(x.toDouble(), 0), Offset(x.toDouble(), x % 100 == 0 ? 10 : 6), ticks);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GuidePainter previous) =>
      kind != previous.kind || center != previous.center || angle != previous.angle || color != previous.color;
}
