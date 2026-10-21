import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../domain/money.dart';
import '../motion/app_motion.dart';
import '../motion/motion_widgets.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/formatters.dart';
import 'pressable.dart';

/// Opción seleccionable en cápsula (categorías, método de pago…).
class ChoiceTag extends StatelessWidget {
  const ChoiceTag({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        haptic: true,
        highlight: false,
        scale: 0.95,
        borderRadius: BorderRadius.circular(20),
        semanticLabel: label,
        child: SelectionPop(
          active: selected,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: AppMotion.ease,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: ShapeDecoration(
              color: selected ? AppColors.accent : AppColors.fill,
              shape: const StadiumBorder(),
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: DefaultTextStyle.of(context).style.merge(AppType.footnote.copyWith(
                    color: selected ? AppColors.onAccent : AppColors.ink,
                    fontWeight: FontWeight.w500,
                  )),
              child: Text(label),
            ),
          ),
        ),
      );
}

/// Selector de moneda en cápsula ("S/ ▾").
class CurrencyMenu extends StatelessWidget {
  const CurrencyMenu({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        initialValue: value,
        onSelected: onChanged,
        tooltip: 'Moneda',
        color: AppColors.surface,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        itemBuilder: (_) => [
          for (final c in kSupportedCurrencies)
            PopupMenuItem(value: c, child: Text('${Fmt.symbol(c)}  $c', style: AppType.body)),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const ShapeDecoration(color: AppColors.fill, shape: StadiumBorder()),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(Fmt.symbol(value), style: AppType.headline),
              const SizedBox(width: 4),
              const Icon(LucideIcons.chevronDown, size: 14, color: AppColors.inkSecondary),
            ],
          ),
        ),
      );
}

/// Selector numérico compacto: [−] valor [+].
class CountStepper extends StatelessWidget {
  const CountStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 99,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, int? next, String label) => Pressable(
          onTap: next == null ? null : () => onChanged(next),
          haptic: true,
          scale: 0.88,
          borderRadius: BorderRadius.circular(18),
          semanticLabel: label,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 16, color: next == null ? AppColors.inkTertiary : AppColors.ink),
          ),
        );

    return Container(
      decoration: const ShapeDecoration(color: AppColors.fill, shape: StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(LucideIcons.minus, value > min ? value - 1 : null, 'Menos'),
          SizedBox(
            width: 28,
            // El número nuevo sube (al aumentar) o baja (al disminuir) como un odómetro.
            child: ClipRect(child: _RollingNumber(value: value)),
          ),
          button(LucideIcons.plus, value < max ? value + 1 : null, 'Más'),
        ],
      ),
    );
  }
}

class _RollingNumber extends StatefulWidget {
  const _RollingNumber({required this.value});
  final int value;

  @override
  State<_RollingNumber> createState() => _RollingNumberState();
}

class _RollingNumberState extends State<_RollingNumber> {
  bool _up = true;

  @override
  void didUpdateWidget(_RollingNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _up = widget.value > old.value;
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: AppMotion.reduced(context) ? Duration.zero : const Duration(milliseconds: 220),
        switchInCurve: AppMotion.ease,
        switchOutCurve: AppMotion.ease,
        transitionBuilder: (child, a) {
          final entering = child.key == ValueKey(widget.value);
          final dir = (_up ? 1.0 : -1.0) * (entering ? 1 : -1);
          return SlideTransition(
            position: Tween(begin: Offset(0, 0.8 * dir), end: Offset.zero).animate(a),
            child: FadeTransition(opacity: a, child: child),
          );
        },
        child: Text(
          '${widget.value}',
          key: ValueKey(widget.value),
          textAlign: TextAlign.center,
          style: AppType.amount,
        ),
      );
}

/// Etiqueta de campo de formulario.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(text, style: AppType.footnote.copyWith(fontWeight: FontWeight.w600)),
      );
}
