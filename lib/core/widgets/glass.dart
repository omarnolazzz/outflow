import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';

/// Material de cristal: desenfoca lo que hay detrás, lo tiñe de blanco
/// translúcido y lo remata con un borde fino luminoso.
///
/// Es caro: úsese solo en superficies pequeñas que flotan sobre el scroll
/// (barra inferior, cabecera, botón "+"), nunca en listas.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(28)),
    this.blur = 24,
    this.tint = AppColors.glassTint,
  });

  final Widget child;
  final BorderRadius radius;
  final double blur;
  final Color tint;

  @override
  Widget build(BuildContext context) => ClipRSuperellipse(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: tint,
              shape: RoundedSuperellipseBorder(
                borderRadius: radius,
                side: const BorderSide(color: AppColors.glassStroke, width: 0.8),
              ),
            ),
            child: child,
          ),
        ),
      );
}
