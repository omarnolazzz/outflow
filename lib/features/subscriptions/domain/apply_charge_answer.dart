import '../../notifications/domain/charge_answer.dart';
import 'charge_schedule.dart';
import 'entities/subscription.dart';

/// Aplica una respuesta de la notificación. null si ya no corresponde (la
/// pregunta se respondió antes en la app o el cobro pendiente es otro).
Subscription? applyChargeAnswer(Subscription s, ChargeAnswer a, DateTime now) {
  if (a.subscriptionId != s.id || s.pendingCharge(now) != a.charge) return null;

  if (a.action == ChargeAnswerAction.cancel) {
    return s.copyWith(status: SubscriptionStatus.cancelled, statusChangedAt: now);
  }
  final next = a.next!;
  // La sugerencia elegida explica la fecha: su patrón es el que se aprende.
  final chosen = suggestNext(s, a.charge).where((x) => x.date == next).firstOrNull;
  return s.confirmCharge(pending: a.charge, chargedOn: a.charge, next: next, pattern: chosen?.pattern);
}
