import 'package:meta/meta.dart';

import '../../../core/domain/billing_cycle.dart';
import 'charge_pattern.dart';
import 'entities/subscription.dart';

/// Fecha propuesta para el próximo cobro y el patrón que la explica.
@immutable
class ChargeSuggestion {
  const ChargeSuggestion({required this.date, required this.pattern, required this.label});
  final DateTime date;
  final ChargePattern pattern;

  /// "Mismo día del mes", "Cada 30 días", "Siguiente día hábil".
  final String label;
}

/// Sugerencias para el cobro siguiente a [chargedOn] (máx. 3, sin fechas
/// repetidas). La del patrón actual de la suscripción va primero.
List<ChargeSuggestion> suggestNext(Subscription s, DateTime chargedOn) {
  final charged = dateOnly(chargedOn);
  final current = s.pattern;
  final cycle = s.cycle;
  final calendar = cycle.unit == CycleUnit.month || cycle.unit == CycleUnit.year;
  final day = current.kind == PatternKind.everyNDays ? charged.day : current.value;

  final candidates = [
    ChargePattern.sameDay(day),
    ChargePattern.everyNDays(
      current.kind == PatternKind.everyNDays ? current.value : _lastInterval(s, charged) ?? cycle.approxDays.round(),
    ),
    if (calendar) ChargePattern.businessDay(day),
  ];
  // El patrón actual primero; el resto conserva su orden.
  final ordered = [
    ...candidates.where((p) => p.kind == current.kind),
    ...candidates.where((p) => p.kind != current.kind),
  ];

  final out = <ChargeSuggestion>[];
  for (final p in ordered) {
    final date = p.nextAfter(charged, cycle);
    if (out.any((o) => o.date == date)) continue;
    out.add(ChargeSuggestion(date: date, pattern: p, label: _label(p, cycle)));
  }
  return out.take(3).toList();
}

String _label(ChargePattern p, BillingCycle cycle) => switch (p.kind) {
      PatternKind.sameDay => cycle.unit == CycleUnit.year ? 'Mismo día del año' : 'Mismo día del mes',
      PatternKind.everyNDays => 'Cada ${p.value} días',
      PatternKind.businessDay => 'Siguiente día hábil',
    };

/// Intervalo real entre el último cobro confirmado y [charged], si es verosímil
/// para el ciclo (evita proponer "cada 3 días" por una confirmación tardía).
int? _lastInterval(Subscription s, DateTime charged) {
  final prev = s.chargeHistory.where((r) => r.confirmed && r.date.isBefore(charged)).lastOrNull;
  if (prev == null) return null;
  final days = charged.difference(prev.date).inDays;
  final expected = s.cycle.approxDays;
  return (days - expected).abs() <= expected * 0.2 ? days : null;
}

/// Patrón que explica los cobros **confirmados** (hacen falta 3 = 2 intervalos).
/// Se prueba en orden: mismo día del mes → día hábil → intervalo fijo (±1 día).
ChargePattern? inferPattern(List<ChargeRecord> history, BillingCycle cycle) {
  final dates = history.where((r) => r.confirmed).map((r) => r.date).toList()..sort();
  if (dates.length < 3) return null;

  if (cycle.unit == CycleUnit.month || cycle.unit == CycleUnit.year) {
    // El día "intencionado" es el mayor: los recortes de fin de mes y los
    // desplazamientos al lunes solo pueden moverlo, no explicarlo.
    for (final day in {for (final d in dates) d.day}.toList()..sort((a, b) => b - a)) {
      if (dates.every((d) => d == _clamped(d, day))) return ChargePattern.sameDay(day);
    }
    for (final day in {for (final d in dates) d.day}.toList()..sort()) {
      if (dates.every((d) => d == _shifted(_clamped(d.subtract(const Duration(days: 2)), day)))) {
        return ChargePattern.businessDay(day);
      }
    }
  }

  final intervals = [for (var i = 1; i < dates.length; i++) dates[i].difference(dates[i - 1]).inDays];
  final min = intervals.reduce((a, b) => a < b ? a : b);
  final max = intervals.reduce((a, b) => a > b ? a : b);
  if (max - min <= 1) {
    return ChargePattern.everyNDays((intervals.reduce((a, b) => a + b) / intervals.length).round());
  }
  return null;
}

/// Día [day] en el mes de [ref], recortado a fin de mes.
DateTime _clamped(DateTime ref, int day) {
  final last = DateTime(ref.year, ref.month + 1, 0).day;
  return DateTime(ref.year, ref.month, day > last ? last : day);
}

DateTime _shifted(DateTime d) => switch (d.weekday) {
      DateTime.saturday => DateTime(d.year, d.month, d.day + 2),
      DateTime.sunday => DateTime(d.year, d.month, d.day + 1),
      _ => d,
    };
