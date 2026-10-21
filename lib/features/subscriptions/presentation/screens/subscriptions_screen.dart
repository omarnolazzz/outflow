import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/di/core_providers.dart';
import '../../../../core/domain/billing_cycle.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/amount_text.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../../merchants/presentation/merchant_providers.dart';
import '../../../merchants/presentation/screens/catalog_screen.dart';
import '../../../shell/presentation/app_shell.dart';
import '../../domain/charges_in_month.dart';
import '../../domain/entities/subscription.dart';
import '../subscription_providers.dart';
import '../widgets/month_calendar.dart';
import '../widgets/subscription_tile.dart';
import 'subscription_detail_screen.dart';

/// Suscripciones: total mensual, calendario con logos y la lista del mes.
class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  DateTime? _month;
  DateTime? _day;

  void _open(Subscription s) => openSubscriptionDetail(context, s.id, heroLogo: true);

  void _add() => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const CatalogScreen()),
      );

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowProvider);
    final today = dateOnly(now);
    final month = _month ?? DateTime(now.year, now.month);
    final subs = ref.watch(subscriptionsProvider).value ?? const <Subscription>[];
    final dashboard = ref.watch(dashboardSummaryProvider).value;
    final merchants = ref.watch(merchantIndexProvider);
    final charges = chargesInMonth(subs, month);

    // Lista del mes (o del día elegido): cada cobro con su estado.
    final entries = <({DateTime date, Subscription s})>[
      for (final MapEntry(key: date, value: list) in charges.entries)
        if (_day == null || date == _day)
          for (final s in list) (date: date, s: s),
    ];
    final inactive = subs.where((s) => !s.status.isBilling).toList();

    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        primary: true,
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 12, bottom: shellBottomInset(context)),
        children: [
          e(Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 6),
            child: Row(
              children: [
                Expanded(child: Text('Suscripciones', style: AppType.largeTitle)),
                Pressable(
                  onTap: _add,
                  highlight: false,
                  scale: 0.9,
                  borderRadius: BorderRadius.circular(20),
                  semanticLabel: 'Añadir suscripción',
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
                    child: const Icon(LucideIcons.plus, size: 20, color: AppColors.accent),
                  ),
                ),
              ],
            ),
          )),
          if (dashboard?.primaryMonthly != null)
            e(Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  AmountText(dashboard!.primaryMonthly!, style: AppType.title2),
                  const SizedBox(width: 6),
                  Text('al mes · ${dashboard.billingCount} activas', style: AppType.subhead),
                ],
              ),
            )),
          e(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SurfaceCard(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
              child: MonthCalendar(
                month: month,
                today: today,
                charges: charges,
                merchants: merchants,
                selected: _day,
                onMonth: (m) => setState(() {
                  _month = m;
                  _day = null;
                }),
                onDay: (d) => setState(() => _day = d),
              ),
            ),
          )),
          e(SectionHeader(
            _day == null ? 'Este mes' : _capitalize(Fmt.dateLong(_day!).replaceAll(RegExp(r' de \d{4}$'), '')),
            action: _day == null ? null : 'Ver todo el mes',
            onAction: () => setState(() => _day = null),
          )),
          e(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: entries.isEmpty
                ? SurfaceCard(
                    child: Text(
                      subs.isEmpty ? 'Aún no tienes suscripciones. Toca + para añadir la primera.' : 'Sin cobros este mes.',
                      style: AppType.subhead,
                    ),
                  )
                : SurfaceCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        for (final x in entries)
                          SubscriptionTile(
                            subscription: x.s,
                            merchant: merchants[x.s.merchantId],
                            now: now,
                            onTap: () => _open(x.s),
                            statusLabel: _status(x.date, today, x.s),
                            statusTone: _tone(x.date, today),
                          ),
                      ],
                    ),
                  ),
          )),
          if (inactive.isNotEmpty) ...[
            e(const SectionHeader('Pausadas y canceladas')),
            e(Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SurfaceCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final s in inactive)
                      SubscriptionTile(subscription: s, merchant: merchants[s.merchantId], now: now, onTap: () => _open(s)),
                  ],
                ),
              ),
            )),
          ],
        ],
      ),
    );
  }

  static String _status(DateTime date, DateTime today, Subscription s) {
    final days = date.difference(today).inDays;
    if (days < 0) return 'Pagado';
    if (days == 0) return 'Hoy';
    if (days == 1) return 'Mañana';
    return 'en $days días';
  }

  static PillTone _tone(DateTime date, DateTime today) {
    final days = date.difference(today).inDays;
    if (days < 0) return PillTone.accent;
    if (days <= 1) return PillTone.danger;
    return PillTone.neutral;
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
