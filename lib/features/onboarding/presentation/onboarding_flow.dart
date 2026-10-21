import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../account/presentation/session_controller.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../wallet/presentation/wallet_providers.dart';
import 'onboarding_controller.dart';
import 'onboarding_steps.dart';

/// Asistente de configuración inicial: un paso por pantalla, barra de
/// progreso y transición lateral entre pasos.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key, required this.state});
  final NeedsOnboarding state;

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  late final OnboardingController _c = OnboardingController(
    short: widget.state.short,
    settings: ref.read(walletSettingsRepositoryProvider),
    movements: ref.read(movementRepositoryProvider),
  );
  bool _finishing = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    await _c.complete(DateTime.now());
    await ref.read(sessionControllerProvider.notifier).finishOnboarding();
  }

  bool _working = false;

  bool get _bioAvailable => ref.read(sessionControllerProvider.notifier).biometricsAvailable;
  String get _bioLabel => ref.read(sessionControllerProvider.notifier).biometricsLabel;

  String _primaryLabel(OnboardingStep step) => switch (step) {
        OnboardingStep.notifications => 'Activar avisos',
        OnboardingStep.faceId when _bioAvailable => 'Activar $_bioLabel',
        OnboardingStep.done => 'Empezar',
        _ => 'Continuar',
      };

  Future<void> _primary(OnboardingStep step) async {
    switch (step) {
      case OnboardingStep.notifications:
        setState(() => _working = true);
        await ref.read(notificationServiceProvider).requestPermission();
        if (mounted) setState(() => _working = false);
        _c.next();
      case OnboardingStep.faceId when _bioAvailable:
        setState(() => _working = true);
        // Se confirma con la cara antes de activarlo.
        final ok = await ref.read(biometricsProvider).authenticate('Activa el desbloqueo de Outflow');
        if (mounted) setState(() => _working = false);
        _c.setFaceId(ok);
        if (ok) _c.next();
      case OnboardingStep.done:
        await _finish();
      default:
        _c.next();
    }
  }

  /// Pasos que se pueden saltar con "Ahora no".
  static const _optional = {
    OnboardingStep.startingBalance,
    OnboardingStep.subscriptions,
    OnboardingStep.notifications,
    OnboardingStep.faceId,
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final step = _c.step;
          final reduced = AppMotion.reduced(context);
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        AnimatedOpacity(
                          opacity: _c.index == 0 ? 0 : 1,
                          duration: AppMotion.short,
                          child: CircleIconButton(
                            icon: LucideIcons.chevronLeft,
                            label: 'Atrás',
                            onTap: _c.index == 0 ? null : _c.back,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: _ProgressBar(value: _c.progress)),
                        const SizedBox(width: 56),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: reduced ? AppMotion.short : const Duration(milliseconds: 380),
                      switchInCurve: AppMotion.ease,
                      switchOutCurve: AppMotion.ease,
                      transitionBuilder: (child, animation) {
                        final fade = FadeTransition(opacity: animation, child: child);
                        if (reduced) return fade;
                        // El que entra viene del lado hacia el que se avanza.
                        final entering = child.key == ValueKey(step);
                        final dx = (_c.forward ? 1 : -1) * (entering ? 0.25 : -0.25);
                        return SlideTransition(
                          position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(animation),
                          child: fade,
                        );
                      },
                      child: KeyedSubtree(key: ValueKey(step), child: buildStep(step, _c)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                    child: Column(
                      children: [
                        PrimaryButton(
                          label: _primaryLabel(step),
                          loading: _finishing || _working,
                          onTap: () => _primary(step),
                        ),
                        SizedBox(
                          height: 44,
                          child: _optional.contains(step)
                              ? Pressable(
                                  onTap: () {
                                    if (step == OnboardingStep.startingBalance) _c.setStartingBalance(0);
                                    if (step == OnboardingStep.faceId) _c.setFaceId(false);
                                    _c.next();
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: const Center(
                                    child: Text(
                                      'Ahora no',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.inkSecondary,
                                      ),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});
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
                tween: Tween(end: value),
                duration: const Duration(milliseconds: 420),
                curve: AppMotion.ease,
                builder: (context, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  heightFactor: 1,
                  widthFactor: v.clamp(0.04, 1.0),
                  child: const ColoredBox(color: AppColors.accent),
                ),
              ),
            ],
          ),
        ),
      );
}
