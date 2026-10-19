import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      secondary: AppColors.ink,
      onSecondary: AppColors.onAccent,
      surface: AppColors.background,
      onSurface: AppColors.ink,
      surfaceContainerHighest: AppColors.surfaceMuted,
      outline: AppColors.border,
      outlineVariant: AppColors.divider,
      error: AppColors.danger,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      // El feedback de presión lo da [Pressable]; sin ondas de tinta Material.
      splashFactory: NoSplash.splashFactory,
      highlightColor: AppColors.pressed,
      dividerColor: AppColors.divider,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppType.headline,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceMuted,
        isDense: true,
        hintStyle: AppType.body.copyWith(color: AppColors.inkTertiary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: _inputBorder(AppColors.border),
        enabledBorder: _inputBorder(AppColors.border),
        focusedBorder: _inputBorder(AppColors.ink),
        errorBorder: _inputBorder(AppColors.danger),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.background),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.accent : AppColors.border,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: AppType.body.copyWith(color: AppColors.onAccent),
        actionTextColor: AppColors.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.background,
        showDragHandle: true,
        dragHandleColor: AppColors.border,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        // Todas las plataformas: la vista previa web (Windows) se mueve igual que el iPhone.
        builders: {
          for (final p in TargetPlatform.values) p: const AdaptivePageTransitionsBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: color, width: 1),
      );
}

/// Transición tipo iOS en ambas plataformas: entra desde la derecha y sale por
/// el mismo camino, con swipe-back interrumpible (se puede agarrar a medio
/// vuelo). Con "reducir movimiento" se sustituye por un fundido corto.
class AdaptivePageTransitionsBuilder extends PageTransitionsBuilder {
  const AdaptivePageTransitionsBuilder();

  static const _cupertino = CupertinoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return FadeTransition(opacity: animation, child: child);
    }
    return _cupertino.buildTransitions(route, context, animation, secondaryAnimation, child);
  }
}
