import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Escala tipográfica con tracking dependiente del tamaño (WWDC 2020,
/// "The Details of UI Typography"): los tamaños grandes se aprietan,
/// los pequeños se abren ligeramente. El leading baja a medida que sube el tamaño.
///
/// Se usa la fuente del sistema (SF en iOS, Roboto en Android): ya trae
/// tamaño óptico y tablas de tracking afinadas.
abstract final class AppType {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Título de página tipo documento ("Suscripciones").
  static const display = TextStyle(
    fontSize: 32,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.64, // ≈ -0.02em
    color: AppColors.ink,
  );

  static const title = TextStyle(
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColors.ink,
  );

  static const headline = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.16,
    color: AppColors.ink,
  );

  static const body = TextStyle(
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.08,
    color: AppColors.ink,
  );

  static const bodyStrong = TextStyle(
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.08,
    color: AppColors.ink,
  );

  /// Etiqueta de sección estilo Notion (gris, pequeña, ligeramente abierta).
  static const section = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: AppColors.inkSecondary,
  );

  static const caption = TextStyle(
    fontSize: 12.5,
    height: 1.35,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.12,
    color: AppColors.inkSecondary,
  );

  /// Cifras: dígitos tabulares para que los montos no "bailen" al cambiar.
  static const amount = TextStyle(
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  static const amountLarge = TextStyle(
    fontSize: 26,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );
}
