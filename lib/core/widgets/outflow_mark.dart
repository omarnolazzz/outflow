import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';

/// Marca de Outflow (flecha ↗ de logo/outflow-icon-*.svg) redibujada como
/// vector, en la versión monocroma de la interfaz: fondo tinta, trazo blanco.
/// Geometría idéntica al SVG original (viewBox 1024, rx 228, trazo 104).
class OutflowMark extends StatelessWidget {
  const OutflowMark({
    super.key,
    this.size = 56,
    this.background = AppColors.ink,
    this.foreground = AppColors.onAccent,
  });

  final double size;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Outflow',
        image: true,
        child: CustomPaint(
          size: Size.square(size),
          painter: _MarkPainter(background, foreground),
        ),
      );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.bg, this.fg);
  final Color bg;
  final Color fg;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 1024;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(228 * s)),
      Paint()..color = bg,
    );
    final arrow = Path()
      ..moveTo(352 * s, 672 * s)
      ..lineTo(672 * s, 352 * s)
      ..moveTo(448 * s, 352 * s)
      ..lineTo(672 * s, 352 * s)
      ..lineTo(672 * s, 576 * s);
    canvas.drawPath(
      arrow,
      Paint()
        ..color = fg
        ..style = PaintingStyle.stroke
        ..strokeWidth = 104 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.bg != bg || old.fg != fg;
}
