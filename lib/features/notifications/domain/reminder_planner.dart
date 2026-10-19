import 'package:meta/meta.dart';

import '../../../core/domain/billing_cycle.dart';
import '../../subscriptions/domain/entities/subscription.dart';
import 'notification_rule.dart';

enum ReminderKind { upcomingCharge, chargeDay, cancellationDeadline }

@immutable
class PlannedReminder {
  const PlannedReminder({
    required this.subscription,
    required this.fireAt,
    required this.kind,
    required this.chargeDate,
    required this.daysBefore,
  });

  final Subscription subscription;
  final DateTime fireAt;
  final ReminderKind kind;

  /// Cobro (o fecha límite de cancelación) al que se refiere el aviso.
  final DateTime chargeDate;
  final int daysBefore;
}

/// Calcula, de forma pura y determinista, qué avisos deben existir.
///
/// No sabe nada de plugins: recibe suscripciones + regla global y devuelve
/// fechas. Así se puede probar con tests unitarios y previsualizar en la UI
/// ("recibirás avisos el 20, 23 y 26 de octubre").
class ReminderPlanner {
  const ReminderPlanner({
    this.horizon = const Duration(days: 62),
    this.maxScheduled = 60,
  });

  /// Ventana rodante: solo se programan avisos dentro de este horizonte y se
  /// reprograma al abrir la app. Evita llenar el sistema de alarmas lejanas.
  final Duration horizon;

  /// iOS permite como máximo 64 notificaciones pendientes por app.
  final int maxScheduled;

  List<PlannedReminder> plan({
    required List<Subscription> subscriptions,
    required NotificationRule globalRule,
    required DateTime now,
  }) {
    final limit = now.add(horizon);
    final out = <PlannedReminder>[];

    for (final sub in subscriptions) {
      if (!sub.status.isBilling) continue;
      final rule = sub.notificationRule ?? globalRule;
      if (!rule.enabled) continue;
      out.addAll(planFor(sub, rule, now: now, until: limit));
    }

    out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
    return out.take(maxScheduled).toList();
  }

  /// Avisos de una sola suscripción (también se usa para la vista previa).
  List<PlannedReminder> planFor(
    Subscription sub,
    NotificationRule rule, {
    required DateTime now,
    required DateTime until,
  }) {
    final out = <PlannedReminder>[];
    final seen = <String>{};

    void add(DateTime day, ReminderKind kind, DateTime ref, int daysBefore) {
      final fireAt = DateTime(day.year, day.month, day.day, rule.hour, rule.minute);
      if (!fireAt.isAfter(now) || fireAt.isAfter(until)) return;
      final key = '${kind.name}|${fireAt.toIso8601String()}';
      if (!seen.add(key)) return;
      out.add(PlannedReminder(
        subscription: sub,
        fireAt: fireAt,
        kind: kind,
        chargeDate: ref,
        daysBefore: daysBefore,
      ));
    }

    // Cobros futuros dentro del horizonte (+ el margen del aviso más lejano).
    final offsets = rule.chargeOffsets;
    final maxLead = offsets.isEmpty ? 0 : offsets.first;
    final charges = <DateTime>[];
    var n = 0;
    final first = sub.cycle.nextOnOrAfter(sub.firstChargeDate, now);
    var charge = first;
    while (!charge.isAfter(until.add(Duration(days: maxLead))) && n < 400) {
      charges.add(charge);
      charge = sub.cycle.nextOnOrAfter(sub.firstChargeDate, charge.add(const Duration(days: 1)));
      n++;
    }

    for (final c in charges) {
      for (final d in offsets) {
        add(
          DateTime(c.year, c.month, c.day - d),
          d == 0 ? ReminderKind.chargeDay : ReminderKind.upcomingCharge,
          c,
          d,
        );
      }
    }

    // Cierre de la ventana de cancelación (incluye el último cobro ya hecho,
    // cuya ventana "después del cobro" puede seguir abierta).
    final window = sub.cancellationWindow;
    if (window != null && rule.remindCancellationDeadline) {
      final last = sub.lastCharge(now);
      for (final c in [?last, ...charges]) {
        final deadline = window.deadlineFor(c);
        final lead = rule.deadlineLeadDays;
        add(
          DateTime(deadline.year, deadline.month, deadline.day - lead),
          ReminderKind.cancellationDeadline,
          dateOnly(deadline),
          lead,
        );
      }
    }

    out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
    return out;
  }
}
