import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/domain/money.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/amount_text.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../domain/month_summary.dart';

/// La wallet: "Te queda este mes" como protagonista, lo que quedará tras los
/// cobros pendientes, la barra de gasto y los totales del mes.
class WalletCard extends StatelessWidget {
  const WalletCard({super.key, required this.summary, required this.onAddIncome});

  final MonthSummary summary;
  final VoidCallback onAddIncome;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final month = toBeginningOfSentenceCase(DateFormat('MMMM', Fmt.locale).format(s.month));
    final hasIncome = s.hasIncome;

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hasIncome ? 'Te queda este mes' : 'Gastado este mes',
                  style: AppType.subhead.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              StatusPill(month),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AmountText(hasIncome ? s.remaining : s.expense, style: AppType.amountHero),
          ),
          if (hasIncome && s.afterPending != s.remaining) ...[
            const SizedBox(height: 4),
            Text(
              '${Fmt.money(s.afterPending)} después de tus cobros pendientes',
              style: AppType.footnote,
            ),
          ],
          if (s.otherCurrencies.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '+ ${s.otherCurrencies.map(Fmt.money).join(' · ')} en otras monedas',
              style: AppType.footnote,
            ),
          ],
          const SizedBox(height: 16),
          if (hasIncome) ...[
            _SpentBar(value: s.spentRatio),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: _Total(
                  icon: LucideIcons.arrowDownLeft,
                  color: AppColors.income,
                  label: 'Ingresos',
                  money: Money(s.income.minor + s.carriedIn.minor, s.income.currency),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Total(icon: LucideIcons.arrowUpRight, color: AppColors.ink, label: 'Gastos', money: s.expense),
              ),
            ],
          ),
          if (!hasIncome) ...[
            const SizedBox(height: 14),
            PillButton(label: 'Registrar ingreso', icon: LucideIcons.plus, filled: true, onTap: onAddIncome),
          ],
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.icon, required this.color, required this.label, required this.money});
  final IconData icon;
  final Color color;
  final String label;
  final Money money;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: ShapeDecoration(
          color: AppColors.background,
          shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 15, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppType.caption),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AmountText(money, style: AppType.amount.copyWith(fontSize: 15)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Barra fina de lo gastado frente a lo disponible; se rellena al aparecer.
class _SpentBar extends StatelessWidget {
  const _SpentBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 6,
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: AppColors.fill)),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: EntranceGate.isOpen(context) ? value : 0),
                duration: AppMotion.reduced(context) ? Duration.zero : const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  heightFactor: 1,
                  widthFactor: v,
                  child: ColoredBox(color: v > 0.9 ? AppColors.danger : AppColors.accent),
                ),
              ),
            ],
          ),
        ),
      );
}
