import 'package:meta/meta.dart';

import '../../../core/domain/billing_cycle.dart';

enum PatternKind {
  /// Mismo día del mes (recortado a fin de mes en meses cortos): Netflix, Spotify.
  sameDay,

  /// Intervalo fijo de días: la fecha "se corre" por el calendario (18 → 19 → 20…),
  /// típico de cortes de tarjeta de crédito.
  everyNDays,

  /// Mismo día del mes, pero si cae en fin de semana pasa al lunes.
  businessDay,
}

/// Cómo avanza un comercio de un cobro al siguiente.
///
/// [value] es el día del mes (sameDay, businessDay) o el número de días
/// (everyNDays). Se guarda el día "intencionado" y no el último cobro, para
/// que un 31 recortado a 28 en febrero vuelva al 31 en marzo.
@immutable
class ChargePattern {
  const ChargePattern._(this.kind, this.value);

  const ChargePattern.sameDay(int day) : this._(PatternKind.sameDay, day);
  const ChargePattern.everyNDays(int days) : this._(PatternKind.everyNDays, days);
  const ChargePattern.businessDay(int day) : this._(PatternKind.businessDay, day);

  final PatternKind kind;
  final int value;

  /// Primer cobro estrictamente posterior a [charge].
  DateTime nextAfter(DateTime charge, BillingCycle cycle) {
    final c = dateOnly(charge);
    return switch (kind) {
      PatternKind.everyNDays => DateTime(c.year, c.month, c.day + value),
      PatternKind.sameDay => _calendarStep(c, cycle),
      // Se parte del mes "intencionado" (3 días antes) por si el cobro anterior
      // ya venía desplazado al mes siguiente (31 may domingo → 1 jun).
      PatternKind.businessDay => _toBusinessDay(_calendarStep(DateTime(c.year, c.month, c.day - 3), cycle)),
    };
  }

  DateTime _calendarStep(DateTime from, BillingCycle cycle) => switch (cycle.unit) {
        CycleUnit.day => DateTime(from.year, from.month, from.day + cycle.every),
        CycleUnit.week => DateTime(from.year, from.month, from.day + 7 * cycle.every),
        CycleUnit.month => _monthWithDay(from, cycle.every),
        CycleUnit.year => _monthWithDay(from, 12 * cycle.every),
      };

  /// Mismo día [value] [months] meses después del mes de [from], recortado a fin de mes.
  DateTime _monthWithDay(DateTime from, int months) {
    final target = DateTime(from.year, from.month + months);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(target.year, target.month, value > lastDay ? lastDay : value);
  }

  static DateTime _toBusinessDay(DateTime d) => switch (d.weekday) {
        DateTime.saturday => DateTime(d.year, d.month, d.day + 2),
        DateTime.sunday => DateTime(d.year, d.month, d.day + 1),
        _ => d,
      };

  /// Mismo tipo de patrón, pero anclado al día de [date] (para fechas elegidas a mano).
  ChargePattern withDayOf(DateTime date) =>
      kind == PatternKind.everyNDays ? this : ChargePattern._(kind, date.day);

  /// Texto para el detalle de la suscripción.
  String describe(BillingCycle cycle) {
    final yearly = cycle.unit == CycleUnit.year;
    return switch (kind) {
      PatternKind.everyNDays => 'Cada $value días',
      PatternKind.sameDay => yearly ? 'Mismo día cada año' : 'Mismo día de cada mes ($value)',
      PatternKind.businessDay => 'Día $value o siguiente día hábil',
    };
  }

  Map<String, Object?> toJson() => {'kind': kind.name, 'value': value};

  factory ChargePattern.fromJson(Map<String, Object?> json) => ChargePattern._(
        PatternKind.values.byName(json['kind'] as String),
        (json['value'] as num).toInt(),
      );

  @override
  bool operator ==(Object other) => other is ChargePattern && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'ChargePattern(${kind.name}, $value)';
}
