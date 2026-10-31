import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/orbit_ring.dart';
import '../../../core/widgets/outflow_mark.dart';
import '../../../core/widgets/primary_button.dart';
import 'account_avatar.dart';
import 'intro_host.dart';
import 'session_controller.dart';

/// Primera pantalla, como la referencia "Login animacion": arriba una
/// ilustración (la marca en órbita rodeada de las suscripciones que Outflow
/// sigue) y abajo una tarjeta que sube con el acceso con Google.
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
        builder: (context, markKey, introRunning) => Column(
          children: [
            Expanded(child: _Hero(markKey: markKey, introRunning: introRunning)),
            Entrance(
              index: 1,
              offset: const Offset(0, 60),
              duration: const Duration(milliseconds: 560),
              child: _card(context),
            ),
          ],
        ),
      );

  Widget _card(BuildContext context) => Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 30, offset: Offset(0, -6))],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                    opacity: _error == null ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: Text(_error ?? '', style: AppType.footnote.copyWith(color: AppColors.danger)),
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
          ),
        ),
      );
}

/// Logos que flotan alrededor de la marca: (archivo, x, y, tamaño, fase).
/// x e y son fracciones del área de la ilustración.
const _bubbles = [
  ('netflix', 0.15, 0.24, 62.0, 0.0),
  ('spotify', 0.84, 0.20, 56.0, 0.35),
  ('disney', 0.12, 0.64, 54.0, 0.6),
  ('chatgpt', 0.88, 0.62, 58.0, 0.15),
  ('youtube_premium', 0.72, 0.88, 48.0, 0.8),
  ('amazon_prime', 0.28, 0.90, 46.0, 0.5),
];

class _Hero extends StatefulWidget {
  const _Hero({required this.markKey, required this.introRunning});
  final GlobalKey markKey;
  final bool introRunning;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> with SingleTickerProviderStateMixin {
  /// Reloj del flote y de la órbita lenta (8 s por vuelta).
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(seconds: 8));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.accentSoft, AppColors.background],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, c) => AnimatedBuilder(
              animation: _loop,
              builder: (context, _) {
                final t = _loop.value;
                return Stack(
                  children: [
                    for (final (i, b) in _bubbles.indexed)
                      Positioned(
                        left: c.maxWidth * b.$2 - b.$4 / 2,
                        top: c.maxHeight * b.$3 - b.$4 / 2 + 6 * math.sin(2 * math.pi * (2 * t + b.$5)),
                        child: Entrance(
                          index: 2 + i,
                          scale: 0.6,
                          offset: Offset.zero,
                          child: _Bubble(asset: 'assets/logos/${b.$1}.png', size: b.$4),
                        ),
                      ),
                    Center(
                      child: SizedBox.square(
                        dimension: 170,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (!widget.introRunning)
                              Entrance(
                                index: 1,
                                offset: Offset.zero,
                                child: OrbitRing(size: 170, angle: t, trail: 0.8),
                              ),
                            Opacity(
                              opacity: widget.introRunning ? 0 : 1,
                              child: OutflowMark(key: widget.markKey, size: 88),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.asset, required this.size});
  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.1),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: ClipOval(child: Image.asset(asset, fit: BoxFit.contain)),
      );
}
