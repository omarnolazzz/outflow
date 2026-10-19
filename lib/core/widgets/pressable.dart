import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../motion/app_motion.dart';
import '../theme/app_colors.dart';

/// Superficie táctil con feedback en *pointer-down*, no al soltar.
///
/// - El resaltado y la escala aparecen en el mismo frame del toque.
/// - La acción se confirma al levantar el dedo (tap-up); arrastrar fuera la cancela.
/// - La escala se anima con un resorte que parte del valor *actual en pantalla*,
///   así que presionar/soltar rápido nunca produce saltos.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.highlight = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.haptic = false,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool highlight;
  final BorderRadius borderRadius;
  final bool haptic;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController.unbounded(vsync: this, value: 0);

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _animateTo(double target) {
    if (AppMotion.reduced(context)) {
      _press.value = target;
      return;
    }
    // Parte del valor y la velocidad presentes: interrumpible sin "muros".
    _press.animateWith(
      SpringSimulation(AppMotion.press, _press.value, target, _press.velocity),
    );
  }

  void _down(PointerDownEvent _) {
    if (!_enabled) return;
    _animateTo(1);
  }

  void _up() => _animateTo(0);

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = AnimatedBuilder(
      animation: _press,
      child: widget.child,
      builder: (context, child) {
        final t = _press.value.clamp(0.0, 1.0);
        final scale = 1 - (1 - widget.scale) * t;
        return Transform.scale(
          scale: scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.highlight
                  ? Color.lerp(const Color(0x00EFEFED), AppColors.pressed, t)
                  : null,
              borderRadius: widget.borderRadius,
            ),
            child: child,
          ),
        );
      },
    );

    return Semantics(
      button: _enabled,
      label: widget.semanticLabel,
      child: Listener(
        onPointerDown: _down,
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Si el scroll gana el gesto, el tap se cancela y el resaltado se suelta.
          onTapCancel: _up,
          onTap: widget.onTap == null
              ? null
              : () {
                  if (widget.haptic) HapticFeedback.selectionClick();
                  widget.onTap!();
                },
          onLongPress: widget.onLongPress,
          child: content,
        ),
      ),
    );
  }
}
