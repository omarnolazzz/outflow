import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import 'pressable.dart';

/// Radio de las tarjetas (esquinas continuas tipo iOS).
const kCardRadius = 22.0;

/// Tarjeta blanca con esquinas continuas y sombra muy difusa. Con [onTap] se
/// hunde levemente al tocarla.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color = AppColors.surface,
    this.radius = kCardRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final card = DecoratedBox(
      decoration: ShapeDecoration(
        color: color,
        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius)),
        shadows: const [
          BoxShadow(color: AppColors.shadow, blurRadius: 24, offset: Offset(0, 8)),
          BoxShadow(color: AppColors.shadow, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return Pressable(
      onTap: onTap,
      highlight: false,
      scale: 0.98,
      borderRadius: BorderRadius.circular(radius),
      child: card,
    );
  }
}
