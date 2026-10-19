import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Resortes expresados como Apple los diseña: `response` (segundos, qué tan
/// rápido llega) y `dampingRatio` (1.0 = sin rebote). Se traducen al trío
/// físico masa/rigidez/amortiguación que usa [SpringSimulation].
abstract final class AppMotion {
  static SpringDescription spring({
    double response = 0.35,
    double dampingRatio = 1.0,
  }) {
    const mass = 1.0;
    final stiffness = math.pow(2 * math.pi / response, 2) * mass;
    final damping = 4 * math.pi * dampingRatio * mass / response;
    return SpringDescription(mass: mass, stiffness: stiffness.toDouble(), damping: damping);
  }

  /// Por defecto: críticamente amortiguado, sin rebote.
  static final standard = spring(response: 0.35);

  /// Feedback de presión: casi instantáneo.
  static final press = spring(response: 0.18);

  /// Solo cuando el gesto trajo inercia (un "flick"): rebote leve.
  static final momentum = spring(response: 0.4, dampingRatio: 0.8);

  /// Curva para transiciones no gestuales (fades de contenido).
  static const ease = Cubic(0.2, 0.0, 0.0, 1.0);
  static const short = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 280);

  /// Movimiento reducido: el sistema pide transiciones mínimas.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
