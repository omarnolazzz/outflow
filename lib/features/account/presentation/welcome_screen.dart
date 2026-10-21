import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/outflow_mark.dart';
import '../../../core/widgets/primary_button.dart';
import 'account_avatar.dart';
import 'intro_host.dart';
import 'session_controller.dart';

/// Primera pantalla: la intro termina en "Bienvenido a Outflow" y un único
/// botón para registrarse o entrar con Google.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref.read(sessionControllerProvider.notifier).continueWithGoogle();
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => IntroHost(
        builder: (context, markKey, introRunning) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(flex: 3),
                Opacity(opacity: introRunning ? 0 : 1, child: OutflowMark(key: markKey, size: 72)),
                const SizedBox(height: 28),
                Entrance(index: 1, child: Text('Bienvenido a Outflow', style: AppType.largeTitle, textAlign: TextAlign.center)),
                const SizedBox(height: 10),
                Entrance(
                  index: 2,
                  child: Text(
                    'Tu wallet y tus suscripciones,\nen un solo lugar.',
                    textAlign: TextAlign.center,
                    style: AppType.body.copyWith(color: AppColors.inkSecondary),
                  ),
                ),
                const Spacer(flex: 4),
                SizedBox(
                  height: 20,
                  child: AnimatedOpacity(
                    opacity: _error == null ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Text(_error ?? '', style: AppType.footnote.copyWith(color: AppColors.danger)),
                  ),
                ),
                const SizedBox(height: 8),
                Entrance(
                  index: 4,
                  offset: const Offset(0, 24),
                  child: PrimaryButton(
                    label: 'Continuar con Google',
                    icon: const GoogleGlyph(),
                    loading: _busy,
                    onTap: _google,
                  ),
                ),
                const SizedBox(height: 14),
                Entrance(
                  index: 5,
                  child: Text(
                    'Tus gastos se guardan cifrados en este iPhone.',
                    textAlign: TextAlign.center,
                    style: AppType.caption.copyWith(color: AppColors.inkTertiary),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      );
}
