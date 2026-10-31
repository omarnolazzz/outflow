import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass.dart';

/// Pestañas de la app.
enum AppTab {
  home('Inicio', LucideIcons.house),
  movements('Historial', LucideIcons.arrowLeftRight),
  subscriptions('Cobros', LucideIcons.calendarSync),
  friends('Amigos', LucideIcons.users),
  summary('Resumen', LucideIcons.chartPie);

  const AppTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Alto de la barra flotante (sin el margen inferior ni el área segura).
const kTabBarHeight = 64.0;

/// Barra de pestañas flotante de cristal. Una píldora marca la pestaña
/// activa y se desliza con un leve rebote al cambiar; el icono "late".
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({super.key, required this.current, required this.onSelect});

  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    const tabs = AppTab.values;
    return BarGlass(
      radius: kTabBarHeight / 2,
      child: SizedBox(
        height: kTabBarHeight,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth - 8) / tabs.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: reduced ? Duration.zero : const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  left: 4 + w * current.index,
                  top: 4,
                  bottom: 4,
                  width: w,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: AppColors.surface.withValues(alpha: 0.9),
                      shape: const StadiumBorder(),
                      shadows: const [BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 2))],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      for (final t in tabs)
                        Expanded(
                          child: _TabItem(
                            tab: t,
                            selected: t == current,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onSelect(t);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.tab, required this.selected, required this.onTap});
  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.inkSecondary;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SelectionPop(
              active: selected,
              amount: 0.12,
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: color),
                duration: AppMotion.short,
                builder: (context, c, _) => Icon(tab.icon, size: 22, color: c),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: AppMotion.short,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
                letterSpacing: -0.1,
              ),
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(tab.label, maxLines: 1, softWrap: false)),
            ),
          ],
        ),
      ),
    );
  }
}
