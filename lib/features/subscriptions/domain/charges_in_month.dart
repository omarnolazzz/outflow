import 'dart:collection';

import '../../../core/domain/billing_cycle.dart';
import 'entities/subscription.dart';

/// Cobros de cada día de [month] (clave: fecha sin hora, ordenadas): los del
/// historial y, para las que siguen cobrando, los proyectados desde el ancla.
SplayTreeMap<DateTime, List<Subscription>> chargesInMonth(List<Subscription> subs, DateTime month) {
  final start = DateTime(month.year, month.month);
  final end = DateTime(month.year, month.month + 1);
  bool inMonth(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  final out = SplayTreeMap<DateTime, List<Subscription>>();
  void add(DateTime d, Subscription s) {
    final list = out.putIfAbsent(dateOnly(d), () => []);
    if (!list.contains(s)) list.add(s);
  }

  for (final s in subs) {
    for (final r in s.chargeHistory) {
      if (inMonth(r.date)) add(r.date, s);
    }
    if (!s.status.isBilling) continue;
    for (final c in s.chargesFrom(start)) {
      if (!c.isBefore(end)) break;
      add(c, s);
    }
  }
  return out;
}
