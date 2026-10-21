import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/di/core_providers.dart';
import '../../../../core/domain/billing_cycle.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/presentation/merchant_providers.dart';
import '../../../merchants/presentation/widgets/merchant_avatar.dart';
import '../../../notifications/domain/notification_rule.dart';
import '../../../notifications/presentation/notification_providers.dart';
import '../../../notifications/presentation/widgets/notification_rule_editor.dart';
import '../../domain/entities/subscription.dart';
import '../subscription_providers.dart';
import '../widgets/confirm_charge_sheet.dart';
import '../widgets/subscription_editor_sheet.dart';
import '../widgets/subscription_tile.dart';

class SubscriptionDetailScreen extends ConsumerWidget {
  const SubscriptionDetailScreen({super.key, required this.subscriptionId, this.heroLogo = false});

  final String subscriptionId;

  /// true si se abre desde la fila de la lista: el logo vuela desde ella.
  final bool heroLogo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(subscriptionByIdProvider(subscriptionId));
    final merchant = s == null ? null : ref.watch(merchantIndexProvider)[s.merchantId];
    final now = ref.watch(nowProvider);

    return SheetScaffold(
      title: '',
      trailing: s == null
          ? null
          : CircleIconButton(
              icon: LucideIcons.pencil,
              label: 'Editar',
              onTap: () => showSubscriptionEditor(context, editing: s, merchant: merchant),
            ),
      // Si la suscripción se elimina mientras está abierta, se muestra un estado vacío.
      child: s == null
          ? Center(child: Text('Esta suscripción ya no existe.', style: AppType.subhead))
          : _DetailBody(subscription: s, merchant: merchant, now: now, heroLogo: heroLogo),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({
    required this.subscription,
    required this.merchant,
    required this.now,
    required this.heroLogo,
  });

  final Subscription subscription;
  final Merchant? merchant;
  final DateTime now;
  final bool heroLogo;

  Future<void> _changeStatus(BuildContext context, WidgetRef ref, SubscriptionStatus status) async {
    final actions = ref.read(subscriptionActionsProvider);
    HapticFeedback.mediumImpact();
    final previous = await actions.setStatus(subscription, status);
    if (!context.mounted) return;

    // Perdón en lugar de confirmación: el cambio es inmediato y reversible.
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (status) {
          SubscriptionStatus.cancelled => 'Marcada como cancelada. Ya no recibirás avisos.',
          SubscriptionStatus.paused => 'Suscripción en pausa.',
          _ => 'Suscripción reactivada.',
        }),
        action: SnackBarAction(label: 'Deshacer', onPressed: () => actions.save(previous)),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    // Eliminar sí es destructivo e irreversible: aquí la confirmación está justificada.
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Eliminar ${subscription.name}?', style: AppType.headline),
        content: Text(
          'Se borrarán su historial y recordatorios; los gastos ya registrados se conservan. '
          'Si solo la diste de baja, márcala como cancelada.',
          style: AppType.subhead,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Conservar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    HapticFeedback.heavyImpact();
    Navigator.of(context).pop();
    await ref.read(subscriptionActionsProvider).delete(subscription.id);
  }

  Future<void> _editReminders(BuildContext context, WidgetRef ref) async {
    final global = ref.read(globalRuleProvider).value;
    final result = await showModalBottomSheet<RuleSheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SubscriptionRuleSheet(subscription: subscription, globalRule: global),
    );
    if (result == null) return;
    await ref
        .read(subscriptionActionsProvider)
        .save(
          result.useGlobal
              ? subscription.copyWith(clearNotificationRule: true)
              : subscription.copyWith(notificationRule: result.rule),
        );
    if (result.rule?.enabled ?? true) {
      await ref.read(notificationServiceProvider).requestPermission();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = subscription;
    final next = s.nextCharge(now);
    final open = s.openWindow(now);
    final pending = s.pendingCharge(now);
    final window = s.cancellationWindow;
    final global = ref.watch(globalRuleProvider).value;
    final logo = merchant?.logo ?? const MerchantLogo.monogram();

    // Cada bloque entra un poco después que el anterior, de arriba abajo.
    var order = 0;
    Widget e(Widget child, {double scale = 1}) => Entrance(index: ++order, scale: scale, child: child);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.paddingOf(context).bottom + 120),
      children: [
        Center(
          child: heroLogo
              ? MerchantAvatar(logo: logo, name: s.name, size: 88, heroTag: subscriptionLogoHeroTag(s.id))
              : Entrance(
                  scale: 0.6,
                  offset: Offset.zero,
                  curve: Curves.easeOutBack,
                  child: MerchantAvatar(logo: logo, name: s.name, size: 88),
                ),
        ),
        const SizedBox(height: 14),
        e(Text(s.name, textAlign: TextAlign.center, style: AppType.title1)),
        const SizedBox(height: 2),
        e(Center(child: CountUp.money(s.price, style: AppType.amountLarge))),
        const SizedBox(height: 10),
        e(
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // El estado cambia con un pequeño "pop" (pausar, cancelar, reactivar).
              AnimatedSwitcher(
                duration: AppMotion.medium,
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: child)),
                child: StatusPill(
                  s.status.label,
                  key: ValueKey(s.status),
                  tone: s.status.isBilling ? PillTone.accent : PillTone.neutral,
                ),
              ),
              if (next != null) ...[
                const SizedBox(width: 8),
                Text(
                  'Próximo cobro ${Fmt.relativeDays(next.difference(dateOnly(now)).inDays).toLowerCase()}',
                  style: AppType.footnote,
                ),
              ],
            ],
          ),
        ),
        if (pending != null) ...[
          const SizedBox(height: 18),
          e(
            scale: 0.96,
            _Callout(
              icon: LucideIcons.calendarCheck,
              title: 'Se cobró el ${Fmt.dateShort(pending)}',
              body: 'Confirma cuándo será el próximo para que las fechas sigan exactas.',
              action: PillButton(
                label: 'Confirmar próximo cobro',
                filled: true,
                onTap: () => showConfirmChargeSheet(context, ref, s, pending),
              ),
            ),
          ),
        ],
        if (open != null) ...[
          const SizedBox(height: 12),
          e(
            scale: 0.96,
            _Callout(
              icon: LucideIcons.hourglass,
              danger: open.deadline.difference(now).inDays <= 1,
              title: 'Plazo de cancelación abierto',
              body: window!.policy == CancellationPolicy.afterCharge
                  ? 'Se cobró el ${Fmt.dateShort(open.chargeDate)}; puedes cancelar y pedir reembolso hasta el ${Fmt.dateLong(open.deadline)}.'
                  : 'Para evitar el cobro del ${Fmt.dateShort(open.chargeDate)} cancela antes del ${Fmt.dateLong(open.deadline)}.',
            ),
          ),
        ],
        const SizedBox(height: 18),
        e(
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _Row(label: 'Frecuencia', value: Fmt.cycle(s.cycle)),
                _Row(label: 'Se renueva el', value: next == null ? '—' : _capitalize(Fmt.dateLong(next))),
                _Row(label: 'Patrón', value: s.pattern.describe(s.cycle)),
                _Row(label: 'Método de pago', value: s.paymentMethod.display),
                _Row(label: 'Categoría', value: s.category.label),
                _Row(
                  label: 'Plazo para cancelar',
                  value: window == null
                      ? 'Sin plazo definido'
                      : window.policy == CancellationPolicy.afterCharge
                          ? '${Fmt.days(window.days)} después del cobro'
                          : 'Avisar ${Fmt.days(window.days)} antes',
                ),
                _Row(
                  label: 'Recordatorios',
                  value: s.notificationRule == null
                      ? 'Generales · ${describeRule(global ?? NotificationRule.defaults)}'
                      : describeRule(s.notificationRule!),
                  onTap: () => _editReminders(context, ref),
                  last: true,
                ),
              ],
            ),
          ),
        ),
        if (s.chargeHistory.isNotEmpty) ...[
          e(const SectionHeader('Últimos cobros')),
          e(
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // Más recientes primero; los asumidos (sin confirmar) en gris.
                for (final r in s.chargeHistory.reversed.take(8))
                  StatusPill(
                    Fmt.dateShort(r.date),
                    tone: r.confirmed ? PillTone.accent : PillTone.neutral,
                    icon: r.confirmed ? LucideIcons.check : null,
                  ),
              ],
            ),
          ),
        ],
        if (s.notes.isNotEmpty) ...[
          e(const SectionHeader('Notas')),
          e(SurfaceCard(child: Text(s.notes, style: AppType.body))),
        ],
        const SizedBox(height: 24),
        e(
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (s.status.isBilling) ...[
                PillButton(
                  label: 'Registrar cancelación',
                  icon: LucideIcons.circleX,
                  onTap: () => _changeStatus(context, ref, SubscriptionStatus.cancelled),
                ),
                PillButton(
                  label: 'Pausar',
                  icon: LucideIcons.circlePause,
                  onTap: () => _changeStatus(context, ref, SubscriptionStatus.paused),
                ),
              ] else
                PillButton(
                  label: 'Reactivar',
                  icon: LucideIcons.rotateCcw,
                  filled: true,
                  onTap: () => _changeStatus(context, ref, SubscriptionStatus.active),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        e(
          Center(
            child: Pressable(
              onTap: () => _delete(context, ref),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  'Eliminar suscripción',
                  style: AppType.callout.copyWith(color: AppColors.danger, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.onTap, this.last = false});
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: AppColors.separator, width: 0.6)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppType.body),
              const SizedBox(width: 16),
              Expanded(
                child: Text(value, textAlign: TextAlign.right, style: AppType.body.copyWith(color: AppColors.inkSecondary)),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(LucideIcons.chevronRight, size: 16, color: AppColors.inkTertiary),
                ),
              ],
            ],
          ),
        ),
      );
}

class _Callout extends StatelessWidget {
  const _Callout({required this.icon, required this.title, required this.body, this.action, this.danger = false});
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.accent;
    return SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.headline),
                const SizedBox(height: 2),
                Text(body, style: AppType.subhead),
                if (action != null) ...[const SizedBox(height: 12), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
