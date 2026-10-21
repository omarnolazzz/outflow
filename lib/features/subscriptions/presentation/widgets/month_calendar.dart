import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/domain/billing_cycle.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/presentation/widgets/merchant_avatar.dart';
import '../../domain/entities/subscription.dart';

/// Calendario mensual con los logos de lo que se cobra cada día. Se cambia
/// de mes con las flechas o deslizando; tocar un día lo selecciona.
class MonthCalendar extends StatefulWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.today,
    required this.charges,
    required this.merchants,
    required this.selected,
    required this.onMonth,
    required this.onDay,
  });

  final DateTime month;
  final DateTime today;
  final Map<DateTime, List<Subscription>> charges;
  final Map<String, Merchant> merchants;
  final DateTime? selected;
  final ValueChanged<DateTime> onMonth;
  final ValueChanged<DateTime?> onDay;

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  /// Dirección del último cambio de mes (para deslizar en ese sentido).
  int _dir = 1;

  void _shift(int delta) {
    HapticFeedback.selectionClick();
    setState(() => _dir = delta);
    widget.onMonth(DateTime(widget.month.year, widget.month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final title = toBeginningOfSentenceCase(DateFormat('MMMM y', Fmt.locale).format(widget.month));
    final reduced = AppMotion.reduced(context);
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() < 250) return;
        _shift(v < 0 ? 1 : -1);
      },
      child: Column(
        children: [
          Row(
            children: [
              CircleIconButton(icon: LucideIcons.chevronLeft, label: 'Mes anterior', onTap: () => _shift(-1)),
              Expanded(child: Text(title, textAlign: TextAlign.center, style: AppType.headline)),
              CircleIconButton(icon: LucideIcons.chevronRight, label: 'Mes siguiente', onTap: () => _shift(1)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final d in const ['L', 'M', 'X', 'J', 'V', 'S', 'D'])
                Expanded(child: Text(d, textAlign: TextAlign.center, style: AppType.caption)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRect(
            child: AnimatedSwitcher(
              duration: reduced ? AppMotion.short : const Duration(milliseconds: 340),
              switchInCurve: AppMotion.ease,
              switchOutCurve: AppMotion.ease,
              layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
              transitionBuilder: (child, a) {
                final fade = FadeTransition(opacity: a, child: child);
                if (reduced) return fade;
                final entering = child.key == ValueKey(widget.month);
                final dx = _dir * (entering ? 0.3 : -0.3);
                return SlideTransition(position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(a), child: fade);
              },
              child: KeyedSubtree(key: ValueKey(widget.month), child: _grid()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid() {
    final first = DateTime(widget.month.year, widget.month.month);
    final days = DateUtils.getDaysInMonth(first.year, first.month);
    final lead = first.weekday - 1; // Lunes primero.
    final cells = lead + days;
    final rows = (cells / 7).ceil();
    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: () {
                    final day = r * 7 + c - lead + 1;
                    if (day < 1 || day > days) return const SizedBox(height: 54);
                    final date = DateTime(first.year, first.month, day);
                    return _DayCell(
                      date: date,
                      isToday: date == dateOnly(widget.today),
                      selected: date == widget.selected,
                      charges: widget.charges[date] ?? const [],
                      merchants: widget.merchants,
                      onTap: () => widget.onDay(date == widget.selected ? null : date),
                    );
                  }(),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isToday,
    required this.selected,
    required this.charges,
    required this.merchants,
    required this.onTap,
  });

  final DateTime date;
  final bool isToday;
  final bool selected;
  final List<Subscription> charges;
  final Map<String, Merchant> merchants;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final has = charges.isNotEmpty;
    return Pressable(
      onTap: has ? onTap : null,
      highlight: false,
      scale: 0.9,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: AppMotion.short,
        height: 54,
        margin: const EdgeInsets.all(2),
        decoration: ShapeDecoration(
          color: selected ? AppColors.accentSoft : (has ? AppColors.background : null),
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: selected ? AppColors.accent : Colors.transparent, width: 1.2),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: isToday ? const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle) : null,
              child: Text(
                '${date.day}',
                style: AppType.footnote.copyWith(
                  color: isToday ? AppColors.onAccent : AppColors.ink,
                  fontWeight: isToday || has ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 18,
              child: has
                  ? TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutBack,
                      builder: (context, t, child) => Transform.scale(scale: t, child: child),
                      child: _Logos(charges: charges, merchants: merchants),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Hasta dos logos superpuestos y "+N" si hay más.
class _Logos extends StatelessWidget {
  const _Logos({required this.charges, required this.merchants});
  final List<Subscription> charges;
  final Map<String, Merchant> merchants;

  @override
  Widget build(BuildContext context) {
    final shown = charges.take(2).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18.0 + (shown.length - 1) * 10,
          height: 18,
          child: Stack(
            children: [
              for (final (i, s) in shown.indexed)
                Positioned(
                  left: i * 10.0,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: AppColors.surface, spreadRadius: 1.2)],
                    ),
                    child: MerchantAvatar(
                      logo: merchants[s.merchantId]?.logo ?? const MerchantLogo.monogram(),
                      name: s.name,
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (charges.length > 2)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text('+${charges.length - 2}', style: AppType.caption.copyWith(fontSize: 9)),
          ),
      ],
    );
  }
}
