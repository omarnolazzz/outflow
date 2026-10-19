import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/di/core_providers.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/notion_widgets.dart';
import '../../../../core/widgets/outflow_mark.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/presentation/merchant_providers.dart';
import '../../../merchants/presentation/screens/catalog_screen.dart';
import '../../../notifications/presentation/screens/settings_screen.dart';
import '../../domain/dashboard_summary.dart';
import '../../domain/entities/subscription.dart';
import '../subscription_providers.dart';
import '../widgets/pending_charge_card.dart';
import '../widgets/subscription_tile.dart';
import '../widgets/upcoming_carousel.dart';
import 'subscription_detail_screen.dart';

/// Pantalla principal con estructura de documento Notion:
///
///   [icono de página]
///   Suscripciones                      ← título tipo documento
///   ◷ Gasto mensual   $123.45          ← propiedades de página
///   ◉ Activas         8
///   ↗ Próximo cobro   Netflix · Mañana
///
///   Próximos cobros                    ← tarjetas deslizables
///   Todas · Activas | Pausadas | …     ← vistas de base de datos
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _scroll = ScrollController();
  SubscriptionStatus _view = SubscriptionStatus.active;

  /// El título grande ocupa ~100px; cuando sale de pantalla aparece el de la barra.
  static const _titleScrollExtent = 96.0;

  /// En la revelación (al desbloquear) las filas esperan a que entre la cabecera;
  /// al cambiar de pestaña entran sin espera.
  bool _wasRevealed = false;
  DateTime? _revealedAt;

  Duration get _rowsDelay {
    final at = _revealedAt;
    final revealing = at != null && DateTime.now().difference(at) < const Duration(milliseconds: 700);
    return revealing ? const Duration(milliseconds: 380) : Duration.zero;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _openDetail(Subscription s, {bool fromList = false}) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SubscriptionDetailScreen(subscriptionId: s.id, heroLogo: fromList),
    ),
  );

  void _openCatalog() =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const CatalogScreen()));

  void _openSettings() =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(dashboardSummaryProvider);
    final merchants = ref.watch(merchantIndexProvider);
    final now = ref.watch(nowProvider);
    final topInset = MediaQuery.paddingOf(context).top;
    final revealed = EntranceGate.isOpen(context);
    if (revealed && !_wasRevealed) _revealedAt = DateTime.now();
    _wasRevealed = revealed;

    return Scaffold(
      body: Stack(
        children: [
          // El contenido pasa por debajo de la barra translúcida.
          switch (summary) {
            AsyncData(:final value) => _buildContent(value, merchants, now, topInset),
            AsyncError(:final error) => Center(child: Text('No se pudieron cargar los datos.\n$error')),
            _ => const SizedBox.shrink(),
          },
          _FloatingBar(
            scroll: _scroll,
            showTitleAfter: _titleScrollExtent,
            onAdd: _openCatalog,
            onSettings: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    DashboardSummary summary,
    Map<String, Merchant> merchants,
    DateTime now,
    double topInset,
  ) {
    final visible = summary.byStatus[_view]!;
    final list = _view == SubscriptionStatus.active
        ? [...visible, ...summary.byStatus[SubscriptionStatus.trial]!]
        : visible;
    if (_view == SubscriptionStatus.active) {
      list.sort((a, b) => a.nextCharge(now)!.compareTo(b.nextCharge(now)!));
    }
    final isEmpty = summary.byStatus.values.every((l) => l.isEmpty);

    return CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(
          child: _PageHeader(summary: summary, now: now, topInset: topInset),
        ),
        if (isEmpty)
          SliverToBoxAdapter(
            child: Entrance(index: 6, child: _EmptyState(onAdd: _openCatalog)),
          )
        else ...[
          if (summary.pending.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Entrance(
                index: 6,
                child: SectionLabel(
                  'Confirma tu próximo cobro',
                  trailing: Text('${summary.pending.length}', style: AppType.caption),
                ),
              ),
            ),
            for (final (i, p) in summary.pending.indexed)
              SliverToBoxAdapter(
                // La tarjeta se va (y las demás se recolocan) al responder.
                child: Entrance(
                  key: ValueKey('pending-${p.subscription.id}-${p.charge}'),
                  index: 7 + i,
                  child: PendingChargeCard(item: p, merchant: merchants[p.subscription.merchantId]),
                ),
              ),
          ],
          if (summary.upcoming.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Entrance(
                index: 6,
                child: SectionLabel(
                  summary.upcoming.any((i) => i.urgency != Urgency.later)
                      ? 'Requiere atención'
                      : 'Próximos cobros',
                  trailing: Text('${summary.upcoming.length}', style: AppType.caption),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: UpcomingCarousel(
                items: summary.upcoming,
                merchants: merchants,
                onOpen: (i) => _openDetail(i.subscription),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: Entrance(
              index: 8,
              child: _ViewTabs(
                current: _view,
                counts: {
                  SubscriptionStatus.active: summary.billingCount,
                  SubscriptionStatus.paused: summary.byStatus[SubscriptionStatus.paused]!.length,
                  SubscriptionStatus.cancelled: summary.byStatus[SubscriptionStatus.cancelled]!.length,
                },
                onChanged: (v) => setState(() => _view = v),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: AppMotion.short,
              switchInCurve: AppMotion.ease,
              switchOutCurve: AppMotion.ease,
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
              child: Column(
                key: ValueKey(_view),
                children: [
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Text(switch (_view) {
                        SubscriptionStatus.paused => 'Nada en pausa.',
                        SubscriptionStatus.cancelled => 'Aún no has cancelado nada.',
                        _ => 'No hay suscripciones activas.',
                      }, style: AppType.body.copyWith(color: AppColors.inkTertiary)),
                    ),
                  for (var i = 0; i < list.length; i++) ...[
                    Entrance(
                      index: i,
                      delay: _rowsDelay,
                      child: SubscriptionTile(
                        subscription: list[i],
                        merchant: merchants[list[i].merchantId],
                        now: now,
                        onTap: () => _openDetail(list[i], fromList: true),
                      ),
                    ),
                    if (i < list.length - 1) const Divider(indent: 68, endIndent: 20),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Entrance(
              delay: _rowsDelay,
              index: list.length,
              child: _NewRow(onTap: _openCatalog),
            ),
          ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 32)),
      ],
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.summary, required this.now, required this.topInset});

  final DashboardSummary summary;
  final DateTime now;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final primary = summary.primaryMonthly;
    final others = summary.monthlyByCurrency.length - 1;
    final nextCharge = summary.upcoming.where((i) => i.kind == UpcomingKind.charge).firstOrNull;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, topInset + 64, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Entrance(scale: 0.7, offset: Offset.zero, child: OutflowMark(size: 44)),
          const SizedBox(height: 16),
          Entrance(index: 1, child: Text('Suscripciones', style: AppType.display)),
          const SizedBox(height: 12),
          Entrance(
            index: 2,
            child: PropertyRow(
              icon: LucideIcons.wallet,
              label: 'Gasto mensual',
              value: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  primary == null
                      ? Text('—', style: AppType.amount)
                      : CountUp.money(primary, style: AppType.amount),
                  if (others > 0)
                    Text('+ $others ${others == 1 ? 'moneda' : 'monedas'}', style: AppType.caption),
                ],
              ),
            ),
          ),
          Entrance(
            index: 3,
            child: PropertyRow(
              icon: LucideIcons.circleCheck,
              label: 'Activas',
              value: CountUp.integer(summary.billingCount, style: AppType.amount),
            ),
          ),
          Entrance(
            index: 4,
            child: PropertyRow(
              icon: LucideIcons.calendarClock,
              label: 'Próximo cobro',
              value: Text(
                nextCharge == null
                    ? 'Sin cobros en 30 días'
                    : '${nextCharge.subscription.name} · ${Fmt.relativeDays(nextCharge.daysLeft)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Entrance(index: 5, offset: Offset.zero, child: Divider()),
        ],
      ),
    );
  }
}

/// Vistas de base de datos Notion: pestañas de texto con subrayado deslizante.
class _ViewTabs extends StatelessWidget {
  const _ViewTabs({required this.current, required this.counts, required this.onChanged});

  final SubscriptionStatus current;
  final Map<SubscriptionStatus, int> counts;
  final ValueChanged<SubscriptionStatus> onChanged;

  static const _labels = {
    SubscriptionStatus.active: 'Activas',
    SubscriptionStatus.paused: 'Pausadas',
    SubscriptionStatus.cancelled: 'Canceladas',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Desplazable: con texto grande del sistema las pestañas no se cortan.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final e in _labels.entries)
                  Pressable(
                    onTap: () => onChanged(e.key),
                    haptic: true,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              AnimatedDefaultTextStyle(
                                duration: AppMotion.short,
                                // Fusiona con el estilo heredado para conservar la familia del tema.
                                style: DefaultTextStyle.of(context).style.merge(
                                  AppType.bodyStrong.copyWith(
                                    color: e.key == current ? AppColors.ink : AppColors.inkTertiary,
                                  ),
                                ),
                                child: Text(e.value),
                              ),
                              const SizedBox(width: 4),
                              Text('${counts[e.key] ?? 0}', style: AppType.caption),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Subrayado que aparece en la vista activa.
                          AnimatedContainer(
                            duration: AppMotion.medium,
                            curve: AppMotion.ease,
                            height: 2,
                            width: e.key == current ? 24 : 0,
                            color: AppColors.ink,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}

/// Fila "+ Nueva" al final de la base de datos, como en Notion.
class _NewRow extends StatelessWidget {
  const _NewRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
    child: Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            const Icon(LucideIcons.plus, size: 18, color: AppColors.inkTertiary),
            const SizedBox(width: 10),
            Text('Nueva suscripción', style: AppType.body.copyWith(color: AppColors.inkTertiary)),
          ],
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NotionCallout(
          emoji: '💡',
          child: Text(
            'Registra tus suscripciones y Outflow te avisará antes de cada cobro, '
            'y antes de que cierre el plazo para cancelar.',
            style: AppType.body,
          ),
        ),
        const SizedBox(height: 16),
        OutlineAction(label: 'Agregar la primera', icon: LucideIcons.plus, filled: true, onTap: onAdd),
      ],
    ),
  );
}

/// Barra superior flotante y translúcida (material de Apple):
/// - El contenido se desplaza por debajo con desenfoque.
/// - El título pequeño y el filo inferior aparecen de forma continua, ligados
///   1:1 al desplazamiento (no se disparan con un umbral).
class _FloatingBar extends StatelessWidget {
  const _FloatingBar({
    required this.scroll,
    required this.showTitleAfter,
    required this.onAdd,
    required this.onSettings,
  });

  final ScrollController scroll;
  final double showTitleAfter;
  final VoidCallback onAdd;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final reduceTransparency = MediaQuery.highContrastOf(context);

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: ListenableBuilder(
        listenable: scroll,
        builder: (context, _) {
          final offset = scroll.hasClients ? scroll.offset : 0.0;
          final material = (offset / 24).clamp(0.0, 1.0);
          final title = ((offset - showTitleAfter) / 24).clamp(0.0, 1.0);

          final bar = Container(
            padding: EdgeInsets.fromLTRB(12, top + 6, 12, 6),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: reduceTransparency ? material : 0.72 * material),
              border: Border(
                bottom: BorderSide(color: AppColors.border.withValues(alpha: material)),
              ),
            ),
            child: Row(
              children: [
                _BarButton(icon: LucideIcons.settings, label: 'Ajustes y recordatorios', onTap: onSettings),
                Expanded(
                  child: Opacity(
                    opacity: title,
                    child: Transform.translate(
                      offset: Offset(0, 6 * (1 - title)),
                      child: Text('Suscripciones', textAlign: TextAlign.center, style: AppType.headline),
                    ),
                  ),
                ),
                _BarButton(icon: LucideIcons.plus, label: 'Nueva suscripción', onTap: onAdd),
              ],
            ),
          );

          if (material == 0 || reduceTransparency) return bar;
          return ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20 * material, sigmaY: 20 * material),
              child: bar,
            ),
          );
        },
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    scale: 0.9,
    semanticLabel: label,
    child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 20, color: AppColors.ink)),
  );
}
