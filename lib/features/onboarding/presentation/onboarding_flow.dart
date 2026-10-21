import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/primary_button.dart';
import '../../account/presentation/session_controller.dart';
import '../../wallet/presentation/wallet_providers.dart';

/// Provisional hasta el asistente de configuración: marca la wallet como empezada.
class OnboardingPlaceholder extends ConsumerWidget {
  const OnboardingPlaceholder({super.key, required this.state});
  final NeedsOnboarding state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: PrimaryButton(
                label: 'Continuar',
                onTap: () async {
                  final repo = ref.read(walletSettingsRepositoryProvider);
                  await repo.save(repo.read().copyWith(onboardingDone: true, walletStartedAt: DateTime.now()));
                  await ref.read(sessionControllerProvider.notifier).finishOnboarding();
                },
              ),
            ),
          ),
        ),
      );
}
