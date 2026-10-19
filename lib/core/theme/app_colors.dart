import 'package:flutter/painting.dart';

/// Paleta "Notion": papel blanco, tinta grafito y un solo acento monocromo.
/// El color se reserva para estados que lo necesitan (error), nunca decoración.
abstract final class AppColors {
  static const background = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF7F7F5);
  static const border = Color(0xFFE1E1E0);
  static const divider = Color(0xFFEDEDEC);

  /// Resaltado al presionar (equivale al hover de Notion: rgba(55,53,47,.08)).
  static const pressed = Color(0xFFEFEFED);

  static const ink = Color(0xFF37352F);
  static const inkSecondary = Color(0xFF787774);
  static const inkTertiary = Color(0xFF9B9A97);
  static const accent = Color(0xFF191919);
  static const onAccent = Color(0xFFFFFFFF);

  /// Único color de estado: errores y cobros vencidos.
  static const danger = Color(0xFFD44C47);
  static const dangerSurface = Color(0xFFFDEBEC);

  /// Callout de Notion (fondo gris cálido).
  static const callout = Color(0xFFF1F1EF);
}
