import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/di/core_providers.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/amount_text.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../../shell/presentation/app_shell.dart';
import '../../domain/category.dart';
import '../../domain/month_summary.dart';
import '../wallet_providers.dart';
import '../widgets/category_icon.dart';

const _monthNames = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String _monthName(DateTime m) => _monthNames[m.month - 1];
String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Resumen: en qué se fue el dinero este mes, frente al anterior y la
/// evolución de ingresos y gastos en los últimos 6 meses.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  DateTime? _month;

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowProvider);
    final current = monthOf(now);
    final month = _month ?? current;
    final months = ref.watch(lastMonthsProvider(month)).value;
    final categories = ref.watch(categoryIndexProvider);
    final summary = months?.last;
    final previous = months == null || months.length < 2 ? null : months[months.length - 2];

    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        primary: true,
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 12, bottom: shellBottomInset(context)),
        children: [
          e(Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Text('Resumen', style: AppType.largeTitle),
          )),
          e(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                CircleIconButton(
                  icon: LucideIcons.chevronLeft,
                  label: 'Mes anterior',
                  onTap: () => setState(() => _month = DateTime(month.year, month.month - 1)),
                ),
                Expanded(
                  child: Text(
                    '${_cap(_monthName(month))} ${month.year}',
                    textAlign: TextAlign.center,
                    style: AppType.headline,
                  ),
                ),
                CircleIconButton(
                  icon: LucideIcons.chevronRight,
                  label: 'Mes siguiente',
                  onTap: month == current ? null : () => setState(() => _month = DateTime(month.year, month.month + 1)),
                ),
              ],
            ),
          )),
          if (summary != null) ...[
            const SizedBox(height: 14),
            e(Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SpendingCard(
                key: ValueKey(month),
                summary: summary,
                previous: previous,
                categories: categories,
              ),
            )),
            e(const SectionHeader('Últimos 6 meses')),
            e(Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SurfaceCard(child: _MonthBars(key: ValueKey(month), months: months!)),
            )),
          ],
        ],
      ),
    );
  }
}

class _SpendingCard extends StatelessWidget {
  const _SpendingCard({super.key, required this.summary, required this.previous, required this.categories});

  final MonthSummary summary;
  final MonthSummary? previous;
  final Map<String, Category> categories;

  @override
  Widget build(BuildContext context) {
    final total = summary.expense.minor;
    final slices = summary.expenseByCategory.entries.toList()..sort((a, b) => b.value.minor.compareTo(a.value.minor));
    final prev = previous?.expense.minor ?? 0;

    String? comparison;
    if (prev > 0) {
      final change = ((total - prev) / prev * 100).round();
      final name = _monthName(previous!.month);
      comparison = change == 0
          ? 'Igual que en $name'
          : '${change.abs()} % ${change > 0 ? 'más' : 'menos'} que en $name';
    }

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gastado', style: AppType.subhead.copyWith(fontWeight: FontWeight.w500)),
          AmountText(summary.expense, style: AppType.amountLarge),
          if (comparison != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  total > prev ? LucideIcons.trendingUp : LucideIcons.trendingDown,
                  size: 15,
                  color: total > prev ? AppColors.danger : AppColors.accent,
                ),
                const SizedBox(width: 4),
                Flexible(child: Text(comparison, style: AppType.footnote)),
              ],
            ),
          ],
          const SizedBox(height: 18),
          if (total == 0)
            Text('Aún no hay gastos este mes.', style: AppType.subhead)
          else ...[
            Center(
              child: SizedBox.square(
                dimension: 190,
                child: _CategoryRing(
                  values: [for (final s in slices) s.value.minor / total],
                  colors: [for (final s in slices) Color(categories[s.key]?.color ?? 0xFF8E8E93)],
                ),
              ),
            ),
            const SizedBox(height: 18),
            for (final (i, s) in slices.indexed)
              Entrance(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      CategoryBadge(category: categories[s.key], size: 32),
                      const SizedBox(width: 10),
                      Expanded(child: Text(categories[s.key]?.name ?? 'Otros', style: AppType.body)),
                      Text(Fmt.money(s.value), style: AppType.amount.copyWith(fontSize: 15)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '${(s.value.minor / total * 100).round()} %',
                          textAlign: TextAlign.right,
                          style: AppType.footnote,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Anillo de categorías que se dibuja con un barrido al aparecer.
class _CategoryRing extends StatelessWidget {
  const _CategoryRing({required this.values, required this.colors});
  final List<double> values;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.reduced(context) ? Duration.zero : const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(painter: _RingPainter(values, colors, t)),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.values, this.colors, this.progress);
  final List<double> values;
  final List<Color> colors;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 22.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    canvas.drawArc(
      arc,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppColors.fill,
    );
    // Separación pequeña entre segmentos; el total visible crece con [progress].
    const gap = 0.035;
    var start = -math.pi / 2;
    final visible = math.pi * 2 * progress;
    var drawn = 0.0;
    for (var i = 0; i < values.length; i++) {
      final sweep = math.pi * 2 * values[i];
      final remaining = visible - drawn;
      if (remaining <= 0) break;
      final s = math.min(sweep, remaining);
      final adjusted = values.length > 1 ? math.max(0.0, s - gap) : s;
      canvas.drawArc(
        arc,
        start,
        adjusted,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = values.length > 1 ? StrokeCap.butt : StrokeCap.round
          ..color = colors[i],
      );
      start += sweep;
      drawn += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.values != values;
}

/// Barras de ingresos (verde) y gastos (tinta) por mes; crecen escalonadas.
class _MonthBars extends StatelessWidget {
  const _MonthBars({super.key, required this.months});
  final List<MonthSummary> months;

  @override
  Widget build(BuildContext context) {
    final maxMinor = months.fold<int>(
      1,
      (m, s) => math.max(m, math.max(s.income.minor + s.carriedIn.minor, s.expense.minor)),
    );
    final reduced = AppMotion.reduced(context);
    return Column(
      children: [
        SizedBox(
          height: 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, m) in months.indexed)
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: reduced ? Duration.zero : Duration(milliseconds: 600 + 70 * i),
                    curve: Interval(reduced ? 0 : (70 * i) / (600 + 70 * i), 1, curve: Curves.easeOutCubic),
                    builder: (context, t, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _Bar(height: 150 * t * (m.income.minor + m.carriedIn.minor) / maxMinor, color: AppColors.income),
                        const SizedBox(width: 3),
                        _Bar(height: 150 * t * m.expense.minor / maxMinor, color: AppColors.ink),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final m in months)
              Expanded(
                child: Text(
                  _cap(_monthName(m.month).substring(0, 3)),
                  textAlign: TextAlign.center,
                  style: AppType.caption,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Legend(color: AppColors.income, label: 'Ingresos'),
            SizedBox(width: 16),
            _Legend(color: AppColors.ink, label: 'Gastos'),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: math.max(height, 2),
        decoration: BoxDecoration(
          color: height <= 0 ? AppColors.fill : color,
          borderRadius: BorderRadius.circular(4),
        ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: AppType.footnote),
        ],
      );
}
