import 'package:meta/meta.dart';

import '../../../core/domain/billing_cycle.dart';
import '../../../core/domain/money.dart';
import 'entities/subscription.dart';

enum Urgency {
  /// Hoy o mañana.
  now,

  /// En 2–3 días.
  soon,

  /// Más adelante.
  later,
}

enum UpcomingKind { charge, cancellationDeadline }

@immutable
class UpcomingItem {
  const UpcomingItem({
    required this.subscription,
    required this.kind,
    required this.date,
    required this.daysLeft,
    required this.cycleProgress,
  });

  final Subscription subscription;
  final UpcomingKind kind;
  final DateTime date;
  final int daysLeft;

  /// 0→1: cuánto del ciclo actual ha transcurrido (o de la ventana de cancelación).
  final double cycleProgress;

  Urgency get urgency => daysLeft <= 1
      ? Urgency.now
      : daysLeft <= 3
          ? Urgency.soon
          : Urgency.later;
}

@immutable
class DashboardSummary {
  const DashboardSummary({
    required this.monthlyByCurrency,
    required this.billingCount,
    required this.upcoming,
    required this.byStatus,
    this.pending = const [],
  });

  /// Gasto mensual equivalente por moneda; primero la más usada.
  final List<Money> monthlyByCurrency;
  final int billingCount;

  /// Cobros y cierres de ventana próximos, ordenados por fecha.
  final List<UpcomingItem> upcoming;
  final Map<SubscriptionStatus, List<Subscription>> byStatus;

  /// Cobros que ya pasaron y esperan confirmación (más antiguos primero).
  final List<PendingCharge> pending;

  Money? get primaryMonthly => monthlyByCurrency.isEmpty ? null : monthlyByCurrency.first;

  /// Caso de uso puro: suscripciones + fecha → resumen.
  factory DashboardSummary.compute(
    List<Subscription> subs,
    DateTime now, {
    int upcomingWindowDays = 30,
    int maxUpcoming = 10,
  }) {
    final today = dateOnly(now);
    final totals = <String, int>{};
    final upcoming = <UpcomingItem>[];
    final pending = <PendingCharge>[];
    final byStatus = {for (final s in SubscriptionStatus.values) s: <Subscription>[]};

    for (final s in subs) {
      byStatus[s.status]!.add(s);
      if (!s.status.isBilling) continue;

      totals.update(s.price.currency, (v) => v + s.monthlyMinor, ifAbsent: () => s.monthlyMinor);

      final asked = s.pendingCharge(today);
      if (asked != null) pending.add(PendingCharge(subscription: s, charge: asked));

      final next = s.nextCharge(today)!;
      final days = next.difference(today).inDays;
      if (days <= upcomingWindowDays) {
        final prev = s.lastCharge(today) ?? s.createdAt;
        final span = next.difference(dateOnly(prev)).inDays;
        upcoming.add(UpcomingItem(
          subscription: s,
          kind: UpcomingKind.charge,
          date: next,
          daysLeft: days,
          cycleProgress: span <= 0 ? 1 : (1 - days / span).clamp(0.0, 1.0),
        ));
      }

      final window = s.openWindow(today);
      if (window != null) {
        final total = window.deadline.difference(window.chargeDate).inDays.abs();
        final left = window.deadline.difference(today).inDays;
        upcoming.add(UpcomingItem(
          subscription: s,
          kind: UpcomingKind.cancellationDeadline,
          date: window.deadline,
          daysLeft: left,
          cycleProgress: total == 0 ? 1 : (1 - left / total).clamp(0.0, 1.0),
        ));
      }
    }

    upcoming.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      // A igual fecha, el cierre de cancelación va primero: es accionable.
      return byDate != 0 ? byDate : b.kind.index.compareTo(a.kind.index);
    });

    for (final list in byStatus.values) {
      list.sort((a, b) {
        final na = a.nextCharge(today), nb = b.nextCharge(today);
        if (na == null || nb == null) return a.name.compareTo(b.name);
        return na.compareTo(nb);
      });
    }

    // Moneda principal = la de más suscripciones (no se comparan importes
    // de monedas distintas).
    final counts = <String, int>{};
    for (final s in subs.where((s) => s.status.isBilling)) {
      counts.update(s.price.currency, (v) => v + 1, ifAbsent: () => 1);
    }
    final monthly = [for (final e in totals.entries) Money(e.value, e.key)]
      ..sort((a, b) => counts[b.currency]!.compareTo(counts[a.currency]!));

    return DashboardSummary(
      monthlyByCurrency: monthly,
      billingCount: byStatus[SubscriptionStatus.active]!.length +
          byStatus[SubscriptionStatus.trial]!.length,
      upcoming: upcoming.take(maxUpcoming).toList(),
      byStatus: byStatus,
      pending: pending..sort((a, b) => a.charge.compareTo(b.charge)),
    );
  }
}

/// Pregunta "confirma tu próximo cobro" de una suscripción.
@immutable
class PendingCharge {
  const PendingCharge({required this.subscription, required this.charge});
  final Subscription subscription;

  /// Cobro previsto que ya pasó.
  final DateTime charge;
}
