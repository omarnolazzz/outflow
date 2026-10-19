import 'package:meta/meta.dart';

import '../../../core/domain/billing_cycle.dart';
import '../../subscriptions/domain/charge_schedule.dart';
import '../../subscriptions/domain/entities/subscription.dart';
import 'notification_rule.dart';

enum ReminderKind {
  upcomingCharge,
  chargeDay,
  cancellationDeadline,

  /// El día siguiente a un cobro: "¿tu próximo cobro es el …?" con botones.
  confirmCharge,
}

@immutable
class PlannedReminder {
  const PlannedReminder({
    required this.subscription,
    required this.fireAt,
    required this.kind,
    required this.chargeDate,
    required this.daysBefore,
    this.suggestions = const [],
  });

  final Subscription subscription;
  final DateTime fireAt;
  final ReminderKind kind;

  /// Cobro (o fecha límite de cancelación) al que se refiere el aviso.
  final DateTime chargeDate;
  final int daysBefore;

  /// confirmCharge: fechas propuestas para el siguiente cobro (máx. 2, la 1ª es la principal).
  final List<DateTime> suggestions;
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
      out.addAll(planConfirmations(sub, rule, now: now, until: limit));
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
    final charges = sub
        .chargesFrom(now)
        .take(400)
        .takeWhile((c) => !c.isAfter(until.add(Duration(days: maxLead))))
        .toList();

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

  /// Preguntas "¿tu próximo cobro es el …?" el día siguiente a cada cobro,
  /// incluida la pendiente de ayer si aún no llegó la hora de hoy.
  List<PlannedReminder> planConfirmations(
    Subscription sub,
    NotificationRule rule, {
    required DateTime now,
    required DateTime until,
  }) {
    if (!sub.status.isBilling) return const [];
    final charges = [
      ?sub.pendingCharge(now),
      ...sub.chargesFrom(now).take(400).takeWhile((c) => c.isBefore(until)),
    ];
    final out = <PlannedReminder>[];
    for (final c in charges) {
      final fireAt = DateTime(c.year, c.month, c.day + 1, rule.hour, rule.minute);
      if (!fireAt.isAfter(now) || fireAt.isAfter(until)) continue;
      out.add(PlannedReminder(
        subscription: sub,
        fireAt: fireAt,
        kind: ReminderKind.confirmCharge,
        chargeDate: c,
        daysBefore: 0,
        suggestions: suggestNext(sub, c).take(2).map((s) => s.date).toList(),
      ));
    }
    return out;
  }
}
