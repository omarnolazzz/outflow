import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/app_motion.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'pressable.dart';

/// Botón ancho en cápsula. Con [loading] se encoge hasta un círculo con un
/// indicador de carga dentro (y vuelve a su ancho si la acción falla).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.loading = false,
    this.secondary = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  /// Variante gris (acción secundaria).
  final bool secondary;
  final Widget? icon;

  static const height = 54.0;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    final bg = secondary ? AppColors.fill : AppColors.accent;
    final fg = secondary ? AppColors.ink : AppColors.onAccent;
    final duration = AppMotion.reduced(context) ? Duration.zero : const Duration(milliseconds: 320);

    return LayoutBuilder(
      builder: (context, c) => Center(
        child: Pressable(
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onTap!();
                }
              : null,
          highlight: false,
          borderRadius: BorderRadius.circular(height / 2),
          semanticLabel: label,
          child: AnimatedContainer(
            duration: duration,
            curve: AppMotion.ease,
            width: loading ? height : c.maxWidth,
            height: height,
            decoration: ShapeDecoration(
              color: onTap == null && !loading ? bg.withValues(alpha: 0.45) : bg,
              shape: const StadiumBorder(),
            ),
            child: AnimatedSwitcher(
              duration: duration,
              child: loading
                  ? SizedBox.square(
                      key: const ValueKey('loading'),
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
                    )
                  : FittedBox(
                      key: const ValueKey('label'),
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icon != null) ...[icon!, const SizedBox(width: 10)],
                            Text(label, style: AppType.headline.copyWith(color: fg)),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
