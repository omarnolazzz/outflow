import 'package:flutter/material.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/outflow_mark.dart';

/// Intro de arranque: la marca aparece y se traza, "Outflow" sube letra a
/// letra con una línea que barre debajo, y al final la marca viaja hasta su
/// sitio en la pantalla de bloqueo ([target]) mientras el resto se desvanece.
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

  /// Marca de la pantalla de bloqueo: destino del viaje.
  final GlobalKey target;
  final bool ready;

  /// Empieza el viaje: el contenido de debajo puede empezar a entrar.
  final VoidCallback onReveal;
  final VoidCallback onDone;

  @override
  State<SplashIntro> createState() => _SplashIntroState();
}

const _word = 'Outflow';
const _size = 72.0;

/// Tiempos en ms sobre la línea de tiempo total.
const _total = 1850.0;
const _hold = 1250.0;

class _SplashIntroState extends State<SplashIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1850),
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
    // Con la marca casi en su sitio, para que el título no entre debajo de ella.
    if (!_revealed && _c.value >= 1550 / _total) {
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
    final fadeOut = 1 - _seg(_hold, 1550);
    final appear = _seg(0, 520, Curves.easeOutBack);
    final markScale = (0.6 + 0.4 * appear) * (1 + (_targetScale - 1) * travel);

    final mark = Transform.translate(
      offset: _delta * travel,
      child: Transform.scale(
        scale: markScale,
        child: Opacity(
          opacity: _seg(0, 250),
          child: OutflowMark(key: _markKey, size: _size, draw: _seg(220, 720, Curves.easeInOutCubic)),
        ),
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
              const SizedBox(height: 20),
              Transform.translate(
                offset: Offset(0, -8 * (1 - fadeOut)),
                child: Opacity(
                  opacity: fadeOut,
                  child: Column(
                    children: [
                      IntrinsicWidth(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < _word.length; i++) _letter(i),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _sweep(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Opacity(
                        opacity: _seg(900, 1200),
                        child: Text('Tu wallet, bajo control', style: AppType.caption),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Cada letra sube y aparece, escalonada.
  Widget _letter(int i) {
    final start = 420.0 + 50 * i;
    final t = _seg(start, start + 420);
    return Transform.translate(
      offset: Offset(0, 14 * (1 - t)),
      child: Opacity(
        opacity: t,
        child: Text(
          _word[i],
          style: AppType.title1.copyWith(fontSize: 30, letterSpacing: 0),
        ),
      ),
    );
  }

  /// Trazo fino que recorre el nombre de izquierda a derecha: la cabeza avanza
  /// y la cola la sigue, como una luz que pasa.
  Widget _sweep() {
    final head = _seg(760, 1040);
    final tail = _seg(900, 1180);
    return CustomPaint(
      painter: _SweepPainter(tail, head),
      child: const SizedBox(height: 1.5),
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter(this.from, this.to);
  final double from;
  final double to;

  @override
  void paint(Canvas canvas, Size size) {
    if (to <= from) return;
    canvas.drawLine(
      Offset(size.width * from, size.height / 2),
      Offset(size.width * to, size.height / 2),
      Paint()
        ..color = AppColors.ink
        ..strokeWidth = size.height
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SweepPainter old) => old.from != from || old.to != to;
}
