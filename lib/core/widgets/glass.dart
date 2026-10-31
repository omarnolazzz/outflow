import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../theme/app_colors.dart';

/// En iPhone la barra inferior usa Liquid Glass (refracción en el borde,
/// brillo y escarcha); en el resto de plataformas, el cristal de siempre.
bool get useLiquidGlass => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Ajustes del cristal líquido de la barra (material "regular" de iOS, claro).
final kBarLiquidSettings = LiquidGlassSettings.ios27Regular(brightness: Brightness.light);

/// Agrupa las piezas de [BarGlass] para que compartan una sola muestra del
/// fondo (lo caro). Sin fusión entre piezas: la barra y el "+" están tan
/// cerca que se unían con un puente de cristal que parecía un reflejo raro.
class BarGlassLayer extends StatelessWidget {
  const BarGlassLayer({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      useLiquidGlass ? LiquidGlassLayer(settings: kBarLiquidSettings, child: child) : child;
}

/// Superficie de la barra flotante: Liquid Glass en iPhone, [Glass] en otros.
class BarGlass extends StatelessWidget {
  const BarGlass({super.key, required this.child, required this.radius, this.tint});

  final Widget child;
  final double radius;

  /// Color del cristal (el botón "+" va teñido); null = cristal neutro.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    if (!useLiquidGlass) {
      return Glass(radius: BorderRadius.circular(radius), tint: tint ?? AppColors.glassTint, child: child);
    }
    return LiquidGlass.auto(
      settings: kBarLiquidSettings,
      shape: LiquidRoundedSuperellipse(borderRadius: radius),
      appearance: tint == null ? null : LiquidGlassAppearance.ios27Regular(brightness: Brightness.light, tint: tint!),
      shadows: const [BoxShadow(color: Color(0x1F000000), offset: Offset(0, 6), blurRadius: 20)],
      child: child,
    );
  }
}

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
