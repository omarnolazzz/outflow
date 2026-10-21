import 'package:flutter/material.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import 'splash_intro.dart';

/// La intro solo se ve en el primer arranque del proceso, no al re-bloquear.
var _introPlayed = false;

/// Pantalla de entrada (bienvenida o bloqueo) con la intro animada encima:
/// la marca viaja hasta [markKey] y el contenido entra escalonado detrás.
class IntroHost extends StatefulWidget {
  const IntroHost({super.key, required this.builder});

  /// Construye el contenido; debe colocar la marca con la `GlobalKey` dada y
  /// ocultarla (opacidad 0) mientras `introRunning`.
  final Widget Function(BuildContext context, GlobalKey markKey, bool introRunning) builder;

  @override
  State<IntroHost> createState() => _IntroHostState();
}

class _IntroHostState extends State<IntroHost> {
  final _markKey = GlobalKey();
  bool? _intro;
  bool _revealed = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro == null) {
      _intro = !_introPlayed && !AppMotion.reduced(context);
      _introPlayed = true;
      _revealed = !_intro!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final intro = _intro ?? false;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          EntranceGate(open: _revealed, child: widget.builder(context, _markKey, intro)),
          if (intro)
            Positioned.fill(
              child: SplashIntro(
                target: _markKey,
                ready: true,
                onReveal: () => setState(() => _revealed = true),
                onDone: () => setState(() => _intro = false),
              ),
            ),
        ],
      ),
    );
  }
}
