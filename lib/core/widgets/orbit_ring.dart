import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';

/// Órbita alrededor de la marca: una estela punteada que se va trazando y un
/// punto que la recorre (como el avión que rodea el planeta en la referencia).
class OrbitRing extends StatelessWidget {
  const OrbitRing({
    super.key,
    required this.size,
    this.trail = 1,
    this.angle = 0,
    this.dot = true,
    this.opacity = 1,
  });

  final double size;

  /// Fracción de la circunferencia trazada (0–1), detrás del punto.
  final double trail;

  /// Posición del punto en vueltas (0 = arriba, 1 = una vuelta).
  final double angle;
  final bool dot;
  final double opacity;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          size: Size.square(size),
          painter: _OrbitPainter(trail.clamp(0.0, 1.0), angle, dot, opacity.clamp(0.0, 1.0)),
        ),
      );
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.trail, this.angle, this.dot, this.opacity);
  final double trail;
  final double angle;
  final bool dot;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity == 0) return;
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final head = -math.pi / 2 + angle * 2 * math.pi;
    final sweep = trail * 2 * math.pi;

    // Estela: guiones cortos desde la cola hasta el punto.
    final dash = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.45 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const dashLen = 0.09; // radianes
    const gap = 0.08;
    for (var a = head - sweep; a < head - 0.12; a += dashLen + gap) {
      final end = math.min(a + dashLen, head - 0.12);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, end - a, false, dash);
    }

    if (!dot) return;
    final p = c + Offset(math.cos(head), math.sin(head)) * r;
    canvas.drawCircle(p, 9, Paint()..color = AppColors.accent.withValues(alpha: 0.16 * opacity));
    canvas.drawCircle(p, 4.5, Paint()..color = AppColors.accent.withValues(alpha: opacity));
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.trail != trail || old.angle != angle || old.dot != dot || old.opacity != opacity;
}
