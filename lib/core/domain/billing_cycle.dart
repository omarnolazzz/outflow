import 'package:meta/meta.dart';

enum CycleUnit { day, week, month, year }

/// Periodicidad de cobro: "cada [every] [unit]" (p. ej. cada 1 mes, cada 3 meses).
///
/// Las fechas se calculan siempre desde el ancla (primer cobro) y no por
/// acumulación, para que un cobro del día 31 caiga el 28/29 en febrero y
/// vuelva al 31 en marzo, sin deriva.
@immutable
class BillingCycle {
  const BillingCycle({required this.unit, this.every = 1}) : assert(every > 0);

  const BillingCycle.monthly() : this(unit: CycleUnit.month);
  const BillingCycle.yearly() : this(unit: CycleUnit.year);

  final CycleUnit unit;
  final int every;

  /// Días aproximados de un ciclo (para ordenar, prorratear y estimar).
  double get approxDays => switch (unit) {
        CycleUnit.day => every.toDouble(),
        CycleUnit.week => every * 7.0,
        CycleUnit.month => every * 30.4375,
        CycleUnit.year => every * 365.25,
      };

  /// Factor para normalizar un monto a gasto mensual.
  double get monthlyFactor => 30.4375 / approxDays;

  /// N-ésimo cobro a partir del [anchor] (n = 0 es el propio ancla).
  DateTime occurrence(DateTime anchor, int n) {
    final a = dateOnly(anchor);
    switch (unit) {
      case CycleUnit.day:
        return DateTime(a.year, a.month, a.day + n * every);
      case CycleUnit.week:
        return DateTime(a.year, a.month, a.day + n * every * 7);
      case CycleUnit.month:
        return _addMonths(a, n * every);
      case CycleUnit.year:
        return _addMonths(a, n * every * 12);
    }
  }

  /// Primer cobro en o después de [from]. Nunca devuelve una fecha anterior al ancla.
  DateTime nextOnOrAfter(DateTime anchor, DateTime from) {
    final a = dateOnly(anchor);
    final f = dateOnly(from);
    if (!f.isAfter(a)) return a;
    var n = (f.difference(a).inDays / approxDays).floor() - 1;
    if (n < 0) n = 0;
    var d = occurrence(a, n);
    while (d.isBefore(f)) {
      d = occurrence(a, ++n);
    }
    return d;
  }

  /// Cobro inmediatamente anterior a [date] (o null si [date] es el primero).
  DateTime? previousBefore(DateTime anchor, DateTime date) {
    final a = dateOnly(anchor);
    final d = dateOnly(date);
    if (!d.isAfter(a)) return null;
    final next = nextOnOrAfter(a, d);
    var n = (next.difference(a).inDays / approxDays).round();
    while (n > 0 && !occurrence(a, n).isBefore(d)) {
      n--;
    }
    final prev = occurrence(a, n);
    return prev.isBefore(d) ? prev : null;
  }

  static DateTime _addMonths(DateTime d, int months) {
    final total = d.month - 1 + months;
    final year = d.year + (total ~/ 12);
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, d.day > lastDay ? lastDay : d.day);
  }

  Map<String, Object?> toJson() => {'unit': unit.name, 'every': every};

  factory BillingCycle.fromJson(Map<String, Object?> json) => BillingCycle(
        unit: CycleUnit.values.byName(json['unit'] as String),
        every: (json['every'] as num?)?.toInt() ?? 1,
      );

  @override
  bool operator ==(Object other) =>
      other is BillingCycle && other.unit == unit && other.every == every;

  @override
  int get hashCode => Object.hash(unit, every);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
