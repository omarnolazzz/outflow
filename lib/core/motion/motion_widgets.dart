import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../domain/money.dart';
import '../utils/formatters.dart';
import 'app_motion.dart';

/// Retiene las [Entrance] mientras está cerrada (p. ej. bajo la pantalla de
/// bloqueo) y las reproduce al abrirse: el contenido se "revela" al desbloquear.
class EntranceGate extends InheritedWidget {
  const EntranceGate({super.key, required this.open, required super.child});
  final bool open;

  static bool isOpen(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EntranceGate>()?.open ?? true;

  @override
  bool updateShouldNotify(EntranceGate oldWidget) => open != oldWidget.open;
}

/// Entrada al aparecer: fundido + desplazamiento corto (+ escala opcional),
/// escalonada por [index]. Se reproduce al montarse (o al abrirse la [EntranceGate]).
///
/// Solo anima opacidad y transformaciones (baratas en GPU); con "reducir
/// movimiento" queda en un fundido sin desplazamiento.
class Entrance extends StatelessWidget {
  const Entrance({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = Duration.zero,
    this.step = const Duration(milliseconds: 45),
    this.offset = const Offset(0, 12),
    this.scale = 1,
    this.duration = const Duration(milliseconds: 420),
    this.curve = AppMotion.ease,
  });

  final Widget child;

  /// Posición en una secuencia: cada índice espera [step] más que el anterior.
  final int index;
  final Duration delay;
  final Duration step;
  final Offset offset;

  /// Escala inicial (1 = sin escala).
  final double scale;
  final Duration duration;

  /// Curva del tramo visible (p. ej. `Curves.easeOutBack` para un leve rebote).
  final Curve curve;

  /// A partir de aquí, las filas fuera de pantalla no esperan.
  static const _maxStagger = 10;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final wait = delay + step * index.clamp(0, _maxStagger);
    final total = wait + duration;
    final start = total == Duration.zero ? 0.0 : wait.inMicroseconds / total.inMicroseconds;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: EntranceGate.isOpen(context) ? 1 : 0),
      duration: reduced ? AppMotion.short : total,
      curve: reduced ? Curves.linear : Interval(start, 1, curve: curve),
      child: child,
      // Misma estructura en todos los frames: el estado del hijo no se reinicia
      // al terminar (Opacity 1 y transformaciones identidad no crean capas).
      builder: (context, t, child) => Transform.translate(
        offset: reduced ? Offset.zero : offset * (1 - t),
        child: Transform.scale(
          scale: reduced ? 1 : scale + (1 - scale) * t,
          // easeOutBack sobrepasa 1: la opacidad se limita, la escala no.
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        ),
      ),
    );
  }
}

/// Pequeño rebote al activarse (seleccionar un tag, un logo, un segmento):
/// un impulso de resorte que crece y vuelve a reposo. Interrumpible.
class SelectionPop extends StatefulWidget {
  const SelectionPop({super.key, required this.active, required this.child, this.amount = 0.08});
  final bool active;
  final Widget child;

  /// Escala extra máxima aproximada (0.08 = +8 %).
  final double amount;

  @override
  State<SelectionPop> createState() => _SelectionPopState();
}

class _SelectionPopState extends State<SelectionPop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this, value: 0);

  @override
  void didUpdateWidget(SelectionPop old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !AppMotion.reduced(context)) {
      // Parte del valor y velocidad actuales: tocar rápido varias veces no salta.
      _c.animateWith(SpringSimulation(AppMotion.momentum, _c.value, 0, _c.velocity + 7));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) =>
            Transform.scale(scale: 1 + _c.value * widget.amount * 2.6, child: child),
      );
}

/// Número que "cuenta" hasta su valor cuando aparece o cambia.
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  /// Importe en moneda.
  CountUp.money(Money money, {Key? key, TextStyle? style})
      : this(
          key: key,
          value: money.major,
          style: style,
          format: (v) => Fmt.money(Money.fromMajor(v, money.currency)),
        );

  /// Entero (contadores).
  CountUp.integer(int value, {Key? key, TextStyle? style})
      : this(
          key: key,
          value: value.toDouble(),
          style: style,
          duration: const Duration(milliseconds: 600),
          format: (v) => '${v.round()}',
        );

  final double value;
  final String Function(double) format;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    // Cifras de ancho fijo: el texto no "tiembla" mientras cuenta.
    final tabular = (style ?? const TextStyle())
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    if (AppMotion.reduced(context)) return Text(format(value), style: tabular);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: EntranceGate.isOpen(context) ? value : 0),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(format(v), style: tabular),
    );
  }
}
