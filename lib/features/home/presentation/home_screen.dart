import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../account/presentation/account_avatar.dart';
import '../../account/presentation/session_controller.dart';
import '../../merchants/presentation/merchant_providers.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../shell/presentation/app_shell.dart';
import '../../subscriptions/domain/dashboard_summary.dart';
import '../../subscriptions/presentation/screens/subscription_detail_screen.dart';
import '../../subscriptions/presentation/subscription_providers.dart';
import '../../subscriptions/presentation/widgets/cancel_question_card.dart';
import '../../subscriptions/presentation/widgets/pending_charge_card.dart';
import '../../subscriptions/presentation/widgets/upcoming_carousel.dart';
import '../../wallet/domain/month_summary.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../../wallet/presentation/widgets/movement_row.dart';
import '../../wallet/presentation/widgets/wallet_card.dart';

/// Inicio: la wallet arriba; debajo, lo próximo que se cobra, las preguntas
/// pendientes y los últimos movimientos.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// La cabecera de cristal aparece cuando el título grande se va por arriba.
  bool _collapsed = false;

  void _openSubscription(String id) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SubscriptionDetailScreen(subscriptionId: id)),
      );

  void _openSettings() => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
      );

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowProvider);
    final month = ref.watch(monthSummaryProvider(monthOf(now))).value;
    final dashboard = ref.watch(dashboardSummaryProvider).value;
    final movements = ref.watch(movementsProvider).value ?? const [];
    final subs = ref.watch(subscriptionsProvider).value ?? const [];
    final categories = ref.watch(categoryIndexProvider);
    final merchants = ref.watch(merchantIndexProvider);
    final account = ref.watch(currentAccountProvider);
    final shell = ShellScope.maybeOf(context);

    final recent = [...movements]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
      });
    final upcoming = dashboard?.upcoming.where((u) => u.kind == UpcomingKind.charge).toList() ?? const [];
    final pending = dashboard?.pending ?? const <PendingCharge>[];
    final cancelQuestions = subs.where((s) => s.cancelQuestionCharge != null).toList();
    final topInset = MediaQuery.paddingOf(context).top;

    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          NotificationListener<ScrollUpdateNotification>(
            onNotification: (n) {
              final collapsed = n.metrics.pixels > 44;
              if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
              return false;
            },
            child: ListView(
              primary: true,
              padding: EdgeInsets.only(top: topInset + 12, bottom: shellBottomInset(context)),
              children: [
                e(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                account == null ? 'Hola' : 'Hola, ${account.firstName}',
                                style: AppType.subhead,
                              ),
                              Text('Inicio', style: AppType.largeTitle),
                            ],
                          ),
                        ),
                        Pressable(
                          onTap: _openSettings,
                          highlight: false,
                          scale: 0.9,
                          borderRadius: BorderRadius.circular(22),
                          semanticLabel: 'Cuenta y ajustes',
                          child: account == null
                              ? const Icon(LucideIcons.settings, color: AppColors.ink)
                              : AccountAvatar(account: account, size: 40),
                        ),
                      ],
                    ),
                  ),
                ),
                if (month != null)
                  e(
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: WalletCard(
                        summary: month,
                        onAddIncome: () => shell?.quickAdd(QuickAction.income),
                      ),
                    ),
                  ),
                if (upcoming.isNotEmpty) ...[
                  e(const SectionHeader('Próximo cobro')),
                  UpcomingCarousel(
                    items: upcoming,
                    merchants: merchants,
                    onOpen: (i) => _openSubscription(i.subscription.id),
                  ),
                ],
                if (pending.isNotEmpty || cancelQuestions.isNotEmpty) ...[
                  e(const SectionHeader('Confirma tu próximo cobro')),
                  for (final q in cancelQuestions)
                    e(CancelQuestionCard(subscription: q, merchant: merchants[q.merchantId])),
                  for (final p in pending)
                    e(PendingChargeCard(item: p, merchant: merchants[p.subscription.merchantId])),
                ],
                e(
                  SectionHeader(
                    'Últimos movimientos',
                    action: recent.isEmpty ? null : 'Ver todos',
                    onAction: () => shell?.select(AppTab.movements),
                  ),
                ),
                e(
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: recent.isEmpty
                        ? SurfaceCard(
                            child: Row(
                              children: [
                                const Icon(LucideIcons.receipt, color: AppColors.inkTertiary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Aún no hay movimientos. Toca + para registrar el primero.',
                                    style: AppType.subhead,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : SurfaceCard(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              children: [
                                for (final m in recent.take(5))
                                  MovementRow(
                                    movement: m,
                                    category: categories[m.categoryId],
                                    merchant: m.subscriptionId == null
                                        ? null
                                        : merchants[subs.where((s) => s.id == m.subscriptionId).firstOrNull?.merchantId],
                                    showDate: true,
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          // Cabecera compacta de cristal al desplazarse.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(
              ignoring: !_collapsed,
              child: AnimatedOpacity(
                opacity: _collapsed ? 1 : 0,
                duration: AppMotion.short,
                child: Glass(
                  radius: BorderRadius.zero,
                  child: SizedBox(
                    height: topInset + 44,
                    child: Padding(
                      padding: EdgeInsets.only(top: topInset),
                      child: Center(child: Text('Inicio', style: AppType.headline)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
