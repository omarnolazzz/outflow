import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/di/core_providers.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/notion_widgets.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/presentation/merchant_providers.dart';
import '../../../merchants/presentation/widgets/merchant_avatar.dart';
import '../../../notifications/domain/notification_rule.dart';
import '../../../notifications/presentation/notification_providers.dart';
import '../../../notifications/presentation/widgets/notification_rule_editor.dart';
import '../../domain/entities/subscription.dart';
import '../subscription_providers.dart';
import '../widgets/subscription_tile.dart';
import 'subscription_form_screen.dart';

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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Atrás',
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (s != null)
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(LucideIcons.pencil, size: 20),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => SubscriptionFormScreen.edit(subscription: s, merchant: merchant),
                ),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      // Si la suscripción se elimina mientras está abierta, se muestra un estado vacío.
      body: s == null
          ? Center(child: Text('Esta suscripción ya no existe.', style: AppType.caption))
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
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('¿Eliminar ${subscription.name}?', style: AppType.headline),
        content: Text(
          'Se borrará su historial y recordatorios. Si solo la diste de baja, '
          'márcala como cancelada para conservar el registro.',
          style: AppType.body.copyWith(color: AppColors.inkSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Conservar', style: AppType.bodyStrong),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Eliminar', style: AppType.bodyStrong.copyWith(color: AppColors.danger)),
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
    final window = s.cancellationWindow;
    final global = ref.watch(globalRuleProvider).value;

    // Cada bloque entra un poco después que el anterior, de arriba abajo.
    var order = 0;
    Widget e(Widget child, {double scale = 1}) => Entrance(index: ++order, scale: scale, child: child);

    return ListView(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.paddingOf(context).bottom + 32),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heroLogo
                  ? MerchantAvatar(
                      logo: merchant?.logo ?? const MerchantLogo.monogram(),
                      name: s.name,
                      size: 56,
                      heroTag: subscriptionLogoHeroTag(s.id),
                    )
                  : Entrance(
                      scale: 0.6,
                      offset: Offset.zero,
                      child: MerchantAvatar(
                        logo: merchant?.logo ?? const MerchantLogo.monogram(),
                        name: s.name,
                        size: 56,
                      ),
                    ),
              const SizedBox(height: 14),
              e(Text(s.name, style: AppType.display.copyWith(fontSize: 28))),
              const SizedBox(height: 8),
              e(
                Row(
                  children: [
                    // El estado cambia con un pequeño "pop" (pausar, cancelar, reactivar).
                    AnimatedSwitcher(
                      duration: AppMotion.medium,
                      switchInCurve: Curves.easeOutBack,
                      transitionBuilder: (child, a) => ScaleTransition(
                        scale: a,
                        child: FadeTransition(opacity: a, child: child),
                      ),
                      child: NotionTag(
                        s.status.label,
                        key: ValueKey(s.status),
                        tone: s.status == SubscriptionStatus.cancelled ? TagTone.neutral : TagTone.strong,
                      ),
                    ),
                    if (next != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        'Próximo cobro ${Fmt.relativeDays(next.difference(DateTime(now.year, now.month, now.day)).inDays).toLowerCase()}',
                        style: AppType.caption,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (open != null) ...[
          const SizedBox(height: 18),
          e(
            scale: 0.96,
            NotionCallout(
              emoji: '⏳',
              tone: open.deadline.difference(now).inDays <= 1 ? TagTone.danger : TagTone.neutral,
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Ventana de cancelación abierta. ',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(
                      text: window!.policy == CancellationPolicy.afterCharge
                          ? 'Se cobró el ${Fmt.dateShort(open.chargeDate)}; puedes cancelar y pedir reembolso hasta el ${Fmt.dateLong(open.deadline)}.'
                          : 'Para evitar el cobro del ${Fmt.dateShort(open.chargeDate)} cancela antes del ${Fmt.dateLong(open.deadline)}.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        const Divider(),
        const SizedBox(height: 6),
        e(
          PropertyRow(
            icon: LucideIcons.banknote,
            label: 'Monto',
            value: CountUp.money(s.price, style: AppType.amount),
          ),
        ),
        e(PropertyRow(icon: LucideIcons.landmark, label: 'Moneda', value: Text(s.price.currency))),
        e(PropertyRow(icon: LucideIcons.tag, label: 'Categoría', value: Text(s.category.label))),
        e(PropertyRow(icon: LucideIcons.repeat, label: 'Ciclo', value: Text(Fmt.cycle(s.cycle)))),
        e(
          PropertyRow(
            icon: LucideIcons.creditCard,
            label: 'Método de pago',
            value: Text(s.paymentMethod.display),
          ),
        ),
        e(
          PropertyRow(
            icon: LucideIcons.calendar,
            label: 'Fecha de cobro',
            value: Text(next == null ? '—' : _capitalize(Fmt.dateLong(next))),
          ),
        ),
        e(
          PropertyRow(
            icon: LucideIcons.hourglass,
            label: 'Ventana de cancelación',
            value: Text(
              window == null
                  ? 'Sin plazo definido'
                  : window.policy == CancellationPolicy.afterCharge
                  ? '${Fmt.days(window.days)} después del cobro'
                  : 'Avisar ${Fmt.days(window.days)} antes del cobro',
            ),
          ),
        ),
        e(
          PropertyRow(
            icon: LucideIcons.bell,
            label: 'Recordatorios',
            onTap: () => _editReminders(context, ref),
            value: Row(
              children: [
                Expanded(
                  child: Text(
                    s.notificationRule == null
                        ? 'Generales · ${describeRule(global ?? NotificationRule.defaults)}'
                        : describeRule(s.notificationRule!),
                  ),
                ),
                const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.inkTertiary),
              ],
            ),
          ),
        ),
        if (s.notes.isNotEmpty) ...[
          const SizedBox(height: 18),
          e(SectionLabel('Notas', padding: const EdgeInsets.fromLTRB(8, 0, 8, 6))),
          e(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(s.notes, style: AppType.body),
            ),
          ),
        ],
        const SizedBox(height: 28),
        e(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (s.status.isBilling) ...[
                  OutlineAction(
                    label: 'Registrar cancelación',
                    icon: LucideIcons.circleX,
                    filled: true,
                    onTap: () => _changeStatus(context, ref, SubscriptionStatus.cancelled),
                  ),
                  OutlineAction(
                    label: 'Pausar',
                    icon: LucideIcons.circlePause,
                    onTap: () => _changeStatus(context, ref, SubscriptionStatus.paused),
                  ),
                ] else
                  OutlineAction(
                    label: 'Reactivar',
                    icon: LucideIcons.rotateCcw,
                    filled: true,
                    onTap: () => _changeStatus(context, ref, SubscriptionStatus.active),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        e(
          Pressable(
            onTap: () => _delete(context, ref),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  const Icon(LucideIcons.trash2, size: 16, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Text('Eliminar suscripción', style: AppType.body.copyWith(color: AppColors.danger)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
