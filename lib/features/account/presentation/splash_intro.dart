import 'package:flutter/material.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/orbit_ring.dart';
import '../../../core/widgets/outflow_mark.dart';

/// Intro de arranque: la marca aparece con un rebote y se traza, un punto la
/// rodea dejando una estela punteada, "Outflow" y su lema suben debajo, y al
/// final la marca viaja hasta su sitio en la pantalla de entrada ([target])
/// mientras el resto se desvanece.
///
/// Se detiene antes del viaje hasta que [ready] (el destino ya existe).
class SplashIntro extends StatefulWidget {
  const SplashIntro({
    super.key,
    required this.target,
    required this.ready,
    required this.onReveal,
    required this.onDone,
  });

  /// Marca de la pantalla de entrada: destino del viaje.
  final GlobalKey target;
  final bool ready;

  /// Empieza el viaje: el contenido de debajo puede empezar a entrar.
  final VoidCallback onReveal;
  final VoidCallback onDone;

  @override
  State<SplashIntro> createState() => _SplashIntroState();
}

const _size = 72.0;
const _orbit = 150.0;

/// Tiempos en ms sobre la línea de tiempo total.
const _total = 2050.0;
const _hold = 1450.0;

class _SplashIntroState extends State<SplashIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2050),
  );
  final _markKey = GlobalKey();
  Offset _delta = Offset.zero;
  double _targetScale = 56 / _size;
  bool _revealed = false;
  bool _traveling = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
    _c.animateTo(_hold / _total).then((_) => _maybeTravel());
  }

  @override
  void didUpdateWidget(SplashIntro old) {
    super.didUpdateWidget(old);
    if (widget.ready && !old.ready) _maybeTravel();
  }

  void _onTick() {
    // Con la marca a medio camino, para que el contenido entre detrás de ella.
    if (!_revealed && _c.value >= 1700 / _total) {
      _revealed = true;
      widget.onReveal();
    }
  }

  /// Arranca el viaje cuando la intro llegó a la pausa y el destino ya existe.
  void _maybeTravel() {
    if (!mounted || !widget.ready || _traveling || _c.value < _hold / _total - 1e-6) return;
    _traveling = true;
    // El destino se coloca en el frame siguiente a quedar listo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final from = _center(_markKey);
      final to = _center(widget.target);
      if (from != null && to != null) _delta = to - from;
      final width = (widget.target.currentContext?.findRenderObject() as RenderBox?)?.size.width;
      if (width != null) _targetScale = width / _size;
      _c.forward().then((_) {
        if (mounted) widget.onDone();
      });
    });
    // En la pausa nada pide frames: hay que provocar uno para la medición.
    WidgetsBinding.instance.scheduleFrame();
  }

  static Offset? _center(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Progreso 0–1 del tramo [from, to] (ms) con [curve].
  double _seg(double from, double to, [Curve curve = AppMotion.ease]) {
    final ms = _c.value * _total;
    return curve.transform(((ms - from) / (to - from)).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(animation: _c, builder: (context, _) => _frame()),
      );

  Widget _frame() {
    final travel = _seg(_hold, _total, Curves.easeInOutCubic);
    final fadeOut = 1 - _seg(_hold, _hold + 300);
    final appear = _seg(0, 520, Curves.easeOutBack);
    final markScale = (0.6 + 0.4 * appear) * (1 + (_targetScale - 1) * travel);

    // El punto da una vuelta y cuarto frenando; la estela lo sigue.
    final orbit = _seg(320, 1350, Curves.easeOutCubic);

    final mark = SizedBox.square(
      dimension: _orbit,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: fadeOut,
            child: OrbitRing(
              size: _orbit,
              angle: 0.2 + 1.25 * orbit,
              trail: 0.92 * orbit,
              opacity: _seg(300, 450),
            ),
          ),
          Transform.translate(
            offset: _delta * travel,
            child: Transform.scale(
              scale: markScale,
              child: Opacity(
                opacity: _seg(0, 250),
                child: OutflowMark(key: _markKey, size: _size, draw: _seg(220, 720, Curves.easeInOutCubic)),
              ),
            ),
          ),
        ],
      ),
    );

    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: AppColors.background.withValues(alpha: fadeOut))),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              const SizedBox(height: 8),
              Opacity(
                opacity: fadeOut,
                child: Column(
                  children: [
                    _rise(
                      _seg(760, 1160),
                      Text('Outflow', style: AppType.title1.copyWith(fontSize: 30, letterSpacing: -0.4)),
                    ),
                    const SizedBox(height: 6),
                    _rise(
                      _seg(940, 1300),
                      Text(
                        'Tu wallet, bajo control',
                        style: AppType.subhead.copyWith(color: AppColors.inkSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Sube unos píxeles mientras aparece.
  static Widget _rise(double t, Widget child) => Transform.translate(
        offset: Offset(0, 12 * (1 - t)),
        child: Opacity(opacity: t, child: child),
      );
}
