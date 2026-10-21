import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/domain/money.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/amount_keypad.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/surface_card.dart';
import '../../account/presentation/session_controller.dart';
import '../../merchants/data/merchant_catalog.dart';
import '../../merchants/presentation/widgets/merchant_avatar.dart';
import '../../notifications/domain/notification_rule.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../subscriptions/presentation/widgets/subscription_editor_sheet.dart';
import '../../subscriptions/presentation/subscription_providers.dart';
import 'onboarding_controller.dart';

Widget buildStep(OnboardingStep step, OnboardingController c) => switch (step) {
      OnboardingStep.currency => _CurrencyStep(c),
      OnboardingStep.startingBalance => _StartingBalanceStep(c),
      OnboardingStep.carryOver => _CarryOverStep(c),
      OnboardingStep.subscriptions => const _SubscriptionsStep(),
      OnboardingStep.notifications => const _NotificationsStep(),
      OnboardingStep.faceId => const _FaceIdStep(),
      OnboardingStep.done => _DoneStep(c),
    };

/// Título grande + explicación, con entrada escalonada.
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Entrance(child: Text(title, style: AppType.largeTitle)),
          if (subtitle != null) ...[
            const SizedBox(height: 10),
            Entrance(
              index: 1,
              child: Text(subtitle!, style: AppType.body.copyWith(color: AppColors.inkSecondary)),
            ),
          ],
        ],
      );
}

const _currencyNames = {
  'PEN': 'Sol peruano',
  'USD': 'Dólar estadounidense',
  'EUR': 'Euro',
  'MXN': 'Peso mexicano',
  'COP': 'Peso colombiano',
  'ARS': 'Peso argentino',
  'CLP': 'Peso chileno',
  'GBP': 'Libra esterlina',
  'BRL': 'Real brasileño',
};

class _CurrencyStep extends StatelessWidget {
  const _CurrencyStep(this.c);
  final OnboardingController c;

  @override
  Widget build(BuildContext context) {
    // La moneda principal primero, luego el resto en el orden de la app.
    final codes = ['PEN', ...kSupportedCurrencies.where((x) => x != 'PEN')];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      children: [
        const _StepHeader(
          title: '¿Con qué moneda manejas tu dinero?',
          subtitle: 'Tu wallet sumará en esta moneda. Puedes cambiarla luego en Ajustes.',
        ),
        const SizedBox(height: 24),
        for (final (i, code) in codes.indexed)
          Entrance(
            index: 2 + i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ChoiceCard(
                selected: c.currency == code,
                onTap: () => c.setCurrency(code),
                leading: Text(Fmt.symbol(code), style: AppType.headline),
                title: _currencyNames[code] ?? code,
                subtitle: code,
              ),
            ),
          ),
      ],
    );
  }
}

class _StartingBalanceStep extends StatefulWidget {
  const _StartingBalanceStep(this.c);
  final OnboardingController c;

  @override
  State<_StartingBalanceStep> createState() => _StartingBalanceStepState();
}

class _StartingBalanceStepState extends State<_StartingBalanceStep> {
  late final AmountInput _input = AmountInput()..setMinor(widget.c.startingBalanceMinor);

  @override
  void initState() {
    super.initState();
    _input.addListener(() => widget.c.setStartingBalance(_input.minor));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StepHeader(
              title: '¿Con cuánto empiezas este mes?',
              subtitle: 'Lo que tienes disponible hoy. Se registra como tu saldo inicial.',
            ),
            const Spacer(),
            Center(
              child: ListenableBuilder(
                listenable: _input,
                builder: (context, _) => FittedBox(
                  child: Text(
                    _input.display(widget.c.currency),
                    style: AppType.amountHero.copyWith(
                      fontSize: 56,
                      color: _input.isEmpty ? AppColors.inkTertiary : AppColors.ink,
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Entrance(index: 2, offset: const Offset(0, 24), child: AmountKeypad(input: _input)),
          ],
        ),
      );
}

class _CarryOverStep extends StatelessWidget {
  const _CarryOverStep(this.c);
  final OnboardingController c;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        children: [
          const _StepHeader(
            title: '¿Lo que te sobre pasa al mes siguiente?',
            subtitle: 'Cada mes tu wallet empieza de nuevo. Puedes arrastrar lo que no gastaste.',
          ),
          const SizedBox(height: 24),
          Entrance(
            index: 2,
            child: _ChoiceCard(
              selected: c.carryOver,
              onTap: () => c.setCarryOver(true),
              leading: const Icon(LucideIcons.arrowRightLeft, size: 22, color: AppColors.accent),
              title: 'Sí, que se sume',
              subtitle: 'Si te sobran S/ 200 en octubre, noviembre empieza con S/ 200.',
            ),
          ),
          const SizedBox(height: 8),
          Entrance(
            index: 3,
            child: _ChoiceCard(
              selected: !c.carryOver,
              onTap: () => c.setCarryOver(false),
              leading: const Icon(LucideIcons.rotateCcw, size: 22, color: AppColors.inkSecondary),
              title: 'No, empezar de cero',
              subtitle: 'Cada mes solo cuenta lo que entra y sale ese mes.',
            ),
          ),
        ],
      );
}

class _SubscriptionsStep extends ConsumerWidget {
  const _SubscriptionsStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final added = {for (final s in ref.watch(subscriptionsProvider).value ?? const []) s.merchantId};
    final popular = MerchantCatalog.all.take(15).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      children: [
        const _StepHeader(
          title: '¿Qué suscripciones tienes?',
          subtitle: 'Toca las que pagas y te avisaremos antes de cada cobro.',
        ),
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.9,
          children: [
            for (final (i, m) in popular.indexed)
              Entrance(
                index: 2 + i,
                scale: 0.85,
                child: SurfaceCard(
                  padding: const EdgeInsets.all(10),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => SubscriptionEditorSheet(merchant: m),
                  )),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          MerchantAvatar(logo: m.logo, name: m.name, size: 48),
                          Positioned(
                            right: -6,
                            top: -6,
                            child: SelectionPop(
                              active: added.contains(m.id),
                              amount: 0.2,
                              child: AnimatedScale(
                                scale: added.contains(m.id) ? 1 : 0,
                                duration: AppMotion.medium,
                                curve: Curves.easeOutBack,
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                                  child: const Icon(LucideIcons.check, size: 14, color: AppColors.onAccent),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        m.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.footnote.copyWith(color: AppColors.ink),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _NotificationsStep extends ConsumerWidget {
  const _NotificationsStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rule = ref.watch(globalRuleProvider).value ?? NotificationRule.defaults;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      children: [
        const _StepHeader(
          title: 'Te avisamos antes de cada cobro',
          subtitle: 'Y al día siguiente te preguntamos si la fecha se mantuvo o varió, '
              'para que tu calendario de cobros sea exacto.',
        ),
        const SizedBox(height: 32),
        const Entrance(
          index: 2,
          scale: 0.7,
          curve: Curves.easeOutBack,
          child: Center(child: _BellBadge()),
        ),
        const SizedBox(height: 32),
        Entrance(
          index: 3,
          child: SurfaceCard(
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: rule.hour, minute: rule.minute),
              );
              if (picked == null) return;
              HapticFeedback.selectionClick();
              await ref
                  .read(notificationSettingsRepositoryProvider)
                  .saveGlobalRule(rule.copyWith(hour: picked.hour, minute: picked.minute));
            },
            child: Row(
              children: [
                const Icon(LucideIcons.clock, size: 20, color: AppColors.inkSecondary),
                const SizedBox(width: 12),
                Expanded(child: Text('Hora de los avisos', style: AppType.body)),
                Text(Fmt.time(rule.hour, rule.minute), style: AppType.headline.copyWith(color: AppColors.accent)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BellBadge extends StatelessWidget {
  const _BellBadge();

  @override
  Widget build(BuildContext context) => Container(
        width: 96,
        height: 96,
        decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
        child: const Icon(LucideIcons.bellRing, size: 44, color: AppColors.accent),
      );
}

class _FaceIdStep extends ConsumerWidget {
  const _FaceIdStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.read(sessionControllerProvider.notifier);
    final label = session.biometricsLabel;
    final available = session.biometricsAvailable;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      children: [
        _StepHeader(
          title: available ? '¿Desbloquear Outflow con $label?' : 'Protege tu wallet',
          subtitle: available
              ? 'Al abrir la app verás el botón "$label" y solo se activará cuando lo pulses.'
              : 'Este dispositivo no tiene $label. Entrarás con tu cuenta de Google.',
        ),
        const SizedBox(height: 40),
        Entrance(
          index: 2,
          scale: 0.7,
          curve: Curves.easeOutBack,
          child: Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
              child: const Icon(LucideIcons.scanFace, size: 44, color: AppColors.accent),
            ),
          ),
        ),
      ],
    );
  }
}

class _DoneStep extends StatelessWidget {
  const _DoneStep(this.c);
  final OnboardingController c;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        child: Column(
          children: [
            const Spacer(),
            const Entrance(
              scale: 0.6,
              curve: Curves.easeOutBack,
              duration: Duration(milliseconds: 600),
              child: _CheckBadge(),
            ),
            const SizedBox(height: 28),
            Entrance(index: 2, child: Text('Todo listo', style: AppType.largeTitle)),
            const SizedBox(height: 10),
            Entrance(
              index: 3,
              child: Text(
                'Tu wallet empieza con',
                style: AppType.body.copyWith(color: AppColors.inkSecondary),
              ),
            ),
            const SizedBox(height: 8),
            Entrance(
              index: 4,
              child: AmountText(Money(c.startingBalanceMinor, c.currency), style: AppType.amountHero),
            ),
            const Spacer(flex: 2),
          ],
        ),
      );
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) => Container(
        width: 96,
        height: 96,
        decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
        child: const Icon(LucideIcons.check, size: 48, color: AppColors.onAccent),
      );
}

/// Opción seleccionable en tarjeta con marca circular animada.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.title,
    this.subtitle,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        haptic: true,
        highlight: false,
        scale: 0.98,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: AppMotion.medium,
          curve: AppMotion.ease,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: ShapeDecoration(
            color: selected ? AppColors.accentSoft : AppColors.surface,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: selected ? AppColors.accent : AppColors.separator, width: selected ? 1.5 : 1),
            ),
          ),
          child: Row(
            children: [
              SizedBox(width: 40, child: Center(child: leading)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppType.headline),
                    if (subtitle != null) Text(subtitle!, style: AppType.footnote),
                  ],
                ),
              ),
              SelectionPop(
                active: selected,
                amount: 0.15,
                child: AnimatedContainer(
                  duration: AppMotion.short,
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.accent : Colors.transparent,
                    border: Border.all(color: selected ? AppColors.accent : AppColors.separator, width: 1.5),
                  ),
                  child: selected ? const Icon(LucideIcons.check, size: 14, color: AppColors.onAccent) : null,
                ),
              ),
            ],
          ),
        ),
      );
}
