import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/pressable.dart';
import 'glass_tab_bar.dart';

enum QuickAction {
  expense('Gasto', LucideIcons.arrowUpRight),
  income('Ingreso', LucideIcons.arrowDownLeft),
  ticket('Escanear ticket', LucideIcons.scanLine),
  subscription('Suscripción', LucideIcons.repeat);

  const QuickAction(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Botón "+" de cristal junto a la barra.
class QuickAddButton extends StatelessWidget {
  const QuickAddButton({super.key, required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        highlight: false,
        scale: 0.9,
        borderRadius: BorderRadius.circular(kTabBarHeight / 2),
        semanticLabel: 'Añadir',
        child: BarGlass(
          radius: kTabBarHeight / 2,
          tint: open ? AppColors.ink.withValues(alpha: 0.85) : AppColors.accent.withValues(alpha: 0.92),
          child: SizedBox.square(
            dimension: kTabBarHeight,
            child: AnimatedRotation(
              turns: open ? 0.125 : 0,
              duration: AppMotion.reduced(context) ? Duration.zero : const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              child: const Icon(LucideIcons.plus, size: 28, color: AppColors.onAccent),
            ),
          ),
        ),
      );
}

/// Velo + acciones que brotan del "+" con un resorte escalonado.
class QuickAddOverlay extends StatelessWidget {
  const QuickAddOverlay({super.key, required this.open, required this.onClose, required this.onAction, this.bottom = 0});

  final bool open;
  final VoidCallback onClose;
  final ValueChanged<QuickAction> onAction;

  /// Distancia desde abajo hasta la parte superior del "+".
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    const actions = QuickAction.values;
    return IgnorePointer(
      ignoring: !open,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: onClose,
              child: AnimatedOpacity(
                opacity: open ? 1 : 0,
                duration: AppMotion.medium,
                child: const ColoredBox(color: Color(0x33000000)),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: bottom + 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, a) in actions.indexed)
                  // La más cercana al "+" sale primero.
                  _ActionPill(
                    action: a,
                    visible: open,
                    delay: Duration(milliseconds: 40 * (actions.length - 1 - i)),
                    reduced: reduced,
                    onTap: () => onAction(a),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.action,
    required this.visible,
    required this.delay,
    required this.reduced,
    required this.onTap,
  });

  final QuickAction action;
  final bool visible;
  final Duration delay;
  final bool reduced;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 360);
    final total = delay + duration;
    final start = delay.inMicroseconds / total.inMicroseconds;
    // Al abrir salen escalonadas con rebote; al cerrar se van todas a la vez, rápido.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: visible ? 1 : 0),
      duration: reduced ? AppMotion.short : (visible ? total : const Duration(milliseconds: 180)),
      curve: visible && !reduced ? Interval(start, 1, curve: Curves.easeOutBack) : Curves.easeIn,
      builder: (context, t, child) => t <= 0
          ? const SizedBox.shrink()
          : Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: reduced ? Offset.zero : Offset(0, 24 * (1 - t)),
                child: Transform.scale(scale: reduced ? 1 : 0.6 + 0.4 * t, alignment: Alignment.centerRight, child: child),
              ),
            ),
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Pressable(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          highlight: false,
          borderRadius: BorderRadius.circular(26),
          child: Container(
            height: 52,
            padding: const EdgeInsets.only(left: 8, right: 18),
            decoration: const ShapeDecoration(
              color: AppColors.surface,
              shape: StadiumBorder(),
              shadows: [BoxShadow(color: Color(0x1F000000), blurRadius: 20, offset: Offset(0, 8))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
                  child: Icon(action.icon, size: 18, color: AppColors.accent),
                ),
                const SizedBox(width: 10),
                Text(action.label, style: AppType.headline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
