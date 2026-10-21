import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Escala tipográfica de iOS (SF Pro vía la fuente del sistema) con tracking
/// dependiente del tamaño: los grandes se aprietan, los pequeños se abren.
/// Las cifras usan dígitos tabulares para que no "bailen" al animarse.
abstract final class AppType {
  static const _tabular = [FontFeature.tabularFigures()];

  static const largeTitle = TextStyle(
    fontSize: 34,
    height: 1.12,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    color: AppColors.ink,
  );

  static const title1 = TextStyle(
    fontSize: 28,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    color: AppColors.ink,
  );

  static const title2 = TextStyle(
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    color: AppColors.ink,
  );

  static const headline = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    color: AppColors.ink,
  );

  static const body = TextStyle(
    fontSize: 17,
    height: 1.35,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.4,
    color: AppColors.ink,
  );

  static const callout = TextStyle(
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.3,
    color: AppColors.ink,
  );

  static const subhead = TextStyle(
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
    color: AppColors.inkSecondary,
  );

  static const footnote = TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.08,
    color: AppColors.inkSecondary,
  );

  static const caption = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.inkSecondary,
  );

  /// El número protagonista (wallet, importe de una hoja).
  static const amountHero = TextStyle(
    fontSize: 48,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.6,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  static const amountLarge = TextStyle(
    fontSize: 34,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -1,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  static const amount = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColors.ink,
    fontFeatures: _tabular,
  );

  // Nombres del estilo anterior, aún usados por pantallas sin migrar.
  // Se eliminan al terminar la migración.
  static const display = title1;
  static const title = title2;
  static const bodyStrong = TextStyle(
    fontSize: 17,
    height: 1.35,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.4,
    color: AppColors.ink,
  );
  static const section = footnote;
}
