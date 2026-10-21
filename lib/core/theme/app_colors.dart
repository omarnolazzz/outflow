import 'package:flutter/painting.dart';

/// Paleta clara estilo iOS: página gris muy claro, tarjetas blancas, tinta
/// casi negra y un único acento esmeralda. El rojo se reserva para vencidos y
/// errores; los gastos van en tinta.
abstract final class AppColors {
  /// Fondo de página (systemGroupedBackground).
  static const background = Color(0xFFF5F5F7);

  /// Tarjetas y hojas.
  static const surface = Color(0xFFFFFFFF);

  /// Rellenos discretos: campos, chips, pistas de barras.
  static const fill = Color(0xFFEFEFF4);

  static const separator = Color(0xFFE5E5EA);

  /// Resaltado al presionar.
  static const pressed = Color(0xFFEBEBF0);

  static const ink = Color(0xFF1C1C1E);
  static const inkSecondary = Color(0xFF6E6E73);
  static const inkTertiary = Color(0xFFAEAEB2);

  static const accent = Color(0xFF0FA47A);
  static const accentSoft = Color(0xFFE2F5EE);
  static const onAccent = Color(0xFFFFFFFF);

  /// Ingresos: mismo verde que el acento.
  static const income = accent;

  static const danger = Color(0xFFE5484D);
  static const dangerSoft = Color(0xFFFDECEC);

  /// Cristal: tinte blanco translúcido y borde luminoso.
  static const glassTint = Color(0xB8FFFFFF);
  static const glassStroke = Color(0x99FFFFFF);

  /// Sombra difusa de tarjetas.
  static const shadow = Color(0x0F000000);

  // Nombres del estilo anterior, aún usados por pantallas sin migrar.
  // Se eliminan al terminar la migración.
  static const surfaceMuted = fill;
  static const border = separator;
  static const divider = separator;
  static const dangerSurface = dangerSoft;
  static const callout = fill;
}
