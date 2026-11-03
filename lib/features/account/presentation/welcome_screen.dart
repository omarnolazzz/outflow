import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/primary_button.dart';
import 'account_avatar.dart';
import 'intro_host.dart';
import 'login_hero.dart';
import 'session_controller.dart';

/// Primera pantalla, como la referencia "Login animacion": arriba la
/// ilustración y abajo una tarjeta que sube con el acceso con Google.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.notice});

  /// Aviso informativo (no es un error), p. ej. que la cuenta se abrió en otro dispositivo.
  final String? notice;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _busy = false;
  String? _error;

  bool _noticeSeen = false;

  String? get shownNotice => _noticeSeen ? null : widget.notice;

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
      _noticeSeen = true;
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
        builder: (context, markKey, introRunning) => Column(
          children: [
            Expanded(child: LoginHero(markKey: markKey, introRunning: introRunning)),
            LoginCard(
              children: [
                Entrance(
                  index: 2,
                  child: Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Bienvenido a\n'),
                      TextSpan(text: 'Outflow', style: AppType.largeTitle.copyWith(color: AppColors.accent)),
                    ]),
                    textAlign: TextAlign.center,
                    style: AppType.largeTitle,
                  ),
                ),
                const SizedBox(height: 10),
                Entrance(
                  index: 3,
                  child: Text(
                    'Tu wallet y tus suscripciones,\nen un solo lugar.',
                    textAlign: TextAlign.center,
                    style: AppType.body.copyWith(color: AppColors.inkSecondary),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 20,
                  child: AnimatedOpacity(
                    opacity: (_error ?? shownNotice) == null ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _error ?? shownNotice ?? '',
                      textAlign: TextAlign.center,
                      style: AppType.footnote.copyWith(
                        color: _error == null ? AppColors.inkSecondary : AppColors.danger,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
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
                    'Tus gastos se guardan cifrados en este teléfono.',
                    textAlign: TextAlign.center,
                    style: AppType.caption.copyWith(color: AppColors.inkTertiary),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
