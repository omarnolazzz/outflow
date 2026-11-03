import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/pressable.dart';
import 'account_avatar.dart';
import 'intro_host.dart';
import 'login_hero.dart';
import 'session_controller.dart';

/// Pantalla de bloqueo, con la misma ilustración que la bienvenida: Face ID
/// solo al pulsar (nunca automático) o volver a verificar la cuenta con Google.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.state});
  final Locked state;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

enum _Busy { none, faceId, google }

class _LockScreenState extends ConsumerState<LockScreen> {
  _Busy _busy = _Busy.none;
  String? _error;

  SessionController get _session => ref.read(sessionControllerProvider.notifier);

  Future<void> _faceId() async {
    setState(() {
      _busy = _Busy.faceId;
      _error = null;
    });
    final ok = await _session.unlockWithFaceId();
    if (!mounted) return;
    if (!ok) HapticFeedback.heavyImpact();
    setState(() => _busy = _Busy.none);
  }

  Future<void> _google() async {
    setState(() {
      _busy = _Busy.google;
      _error = null;
    });
    final error = await _session.continueWithGoogle();
    if (!mounted) return;
    setState(() {
      _busy = _Busy.none;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.state.account;
    return IntroHost(
      builder: (context, markKey, introRunning) => Column(
        children: [
          Expanded(child: LoginHero(markKey: markKey, introRunning: introRunning)),
          LoginCard(
            children: [
              Entrance(
                index: 2,
                scale: 0.8,
                child: AccountAvatar(account: account, size: 56),
              ),
              const SizedBox(height: 10),
              Entrance(index: 3, child: Text('Hola, ${account.firstName}', style: AppType.title1)),
              const SizedBox(height: 2),
              Entrance(index: 3, child: Text(account.email, style: AppType.subhead)),
              const SizedBox(height: 8),
              SizedBox(
                height: 20,
                child: AnimatedOpacity(
                  opacity: _error == null ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: Text(_error ?? '', style: AppType.footnote.copyWith(color: AppColors.danger)),
                ),
              ),
              const SizedBox(height: 6),
              if (widget.state.faceId) ...[
                Entrance(
                  index: 4,
                  offset: const Offset(0, 24),
                  child: PrimaryButton(
                    label: 'Desbloquear con ${widget.state.faceIdLabel}',
                    icon: const Icon(LucideIcons.scanFace, size: 20, color: AppColors.onAccent),
                    loading: _busy == _Busy.faceId,
                    onTap: _busy == _Busy.none ? _faceId : null,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Entrance(
                index: 5,
                offset: const Offset(0, 24),
                child: PrimaryButton(
                  label: 'Continuar con Google',
                  icon: const GoogleGlyph(),
                  secondary: widget.state.faceId,
                  loading: _busy == _Busy.google,
                  onTap: _busy == _Busy.none ? _google : null,
                ),
              ),
              // Sin Face ID activado, el bloqueo del teléfono siempre sirve (también sin red).
              if (!widget.state.faceId) ...[
                const SizedBox(height: 8),
                Pressable(
                  onTap: _faceId,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      'Usar el bloqueo del teléfono',
                      style: AppType.callout.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
