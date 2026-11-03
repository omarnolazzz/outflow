import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/orbit_ring.dart';
import '../../../core/widgets/outflow_mark.dart';

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

/// Por debajo de este alto los logos taparían la marca: solo queda la órbita.
const _minHeightForBubbles = 240.0;

/// Ilustración de las pantallas de entrada (bienvenida y bloqueo): la marca en
/// órbita rodeada de las suscripciones que Outflow sigue, flotando.
class LoginHero extends StatefulWidget {
  const LoginHero({super.key, required this.markKey, required this.introRunning});

  /// Destino del viaje de la marca en la intro.
  final GlobalKey markKey;
  final bool introRunning;

  @override
  State<LoginHero> createState() => _LoginHeroState();
}

class _LoginHeroState extends State<LoginHero> with SingleTickerProviderStateMixin {
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
            builder: (context, c) {
              // En pantallas bajas la órbita y la marca encogen para caber.
              final orbit = math.min(170.0, c.maxHeight * 0.8);
              return AnimatedBuilder(
                animation: _loop,
                builder: (context, _) {
                  final t = _loop.value;
                  return Stack(
                    children: [
                      if (c.maxHeight >= _minHeightForBubbles)
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
                          dimension: orbit,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (!widget.introRunning)
                                Entrance(
                                  index: 1,
                                  offset: Offset.zero,
                                  child: OrbitRing(size: orbit, angle: t, trail: 0.8),
                                ),
                              Opacity(
                                opacity: widget.introRunning ? 0 : 1,
                                child: OutflowMark(key: widget.markKey, size: orbit * 0.52),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
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

/// Tarjeta blanca que sube desde abajo con las acciones de entrada.
class LoginCard extends StatelessWidget {
  const LoginCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Entrance(
        index: 1,
        offset: const Offset(0, 60),
        duration: const Duration(milliseconds: 560),
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 30, offset: Offset(0, -6))],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ),
      );
}
