import '../../../core/domain/billing_cycle.dart';
import '../../subscriptions/domain/entities/subscription.dart';
import 'category.dart';
import 'month_summary.dart';
import 'movement.dart';
import 'wallet_settings.dart';

/// Id estable del gasto de un cobro: una suscripción y una fecha.
String chargeMovementId(String subscriptionId, DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'sub:$subscriptionId:${date.year}-${two(date.month)}-${two(date.day)}';
}

/// Cambios que llevan los gastos de suscripciones a reflejar sus cobros.
typedef ChargeMovementChanges = ({List<Movement> upsert, List<String> delete});

/// Concilia los gastos automáticos con los cobros de cada suscripción.
///
/// Cobros de una suscripción (desde el mes en que empezó la wallet hasta hoy):
/// - los del historial (confirmados, o asumidos = provisionales);
/// - los proyectados desde el ancla, si está activa (no en prueba);
/// - el de la pregunta "¿Te llegaron a cobrar?" pendiente (provisional).
///
/// Se crean los que faltan (salvo los que el usuario borró), se actualizan
/// los provisionales y su importe (salvo editados a mano), y se borran los
/// provisionales que ya no corresponden. Los gastos de suscripciones borradas
/// no se tocan: ocurrieron.
ChargeMovementChanges reconcileChargeMovements({
  required List<Subscription> subscriptions,
  required List<Movement> existing,
  required WalletSettings settings,
  required DateTime now,
}) {
  final started = settings.walletStartedAt;
  if (started == null) return (upsert: const [], delete: const []);
  final from = monthOf(started);
  final today = dateOnly(now);

  final byId = {
    for (final m in existing)
      if (m.origin == MovementOrigin.subscription) m.id: m,
  };
  final upsert = <Movement>[];
  final delete = <String>[];

  for (final s in subscriptions) {
    // fecha → provisional
    final occurrences = <DateTime, bool>{};
    bool inRange(DateTime d) => !d.isBefore(from) && !d.isAfter(today);

    for (final r in s.chargeHistory) {
      if (inRange(r.date)) occurrences[r.date] = !r.confirmed && (occurrences[r.date] ?? true);
    }
    if (s.status == SubscriptionStatus.active) {
      for (final c in s.chargesFrom(from)) {
        if (c.isAfter(today)) break;
        occurrences.putIfAbsent(c, () => true);
      }
    }
    final q = s.cancelQuestionCharge;
    if (q != null && inRange(dateOnly(q))) occurrences.putIfAbsent(dateOnly(q), () => true);

    final ids = {for (final d in occurrences.keys) chargeMovementId(s.id, d)};

    // Provisionales que ya no son cobros. Solo se borran si una respuesta los
    // sustituyó (hay un cobro del historial desde 20 días antes, el margen con
    // el que se corrige la fecha real) o si aún no han llegado. Pausar,
    // cancelar o cambiar la fecha no borra lo que ya pasó sin respuesta.
    final superseded = <Movement>[];
    for (final m in byId.values) {
      if (m.subscriptionId != s.id || ids.contains(m.id) || !m.provisional) continue;
      final d = dateOnly(m.date);
      final answered = s.chargeHistory.any((r) => !r.date.isBefore(d.subtract(const Duration(days: 20))));
      if (d.isAfter(today) || answered) {
        delete.add(m.id);
        superseded.add(m);
      }
    }

    for (final MapEntry(key: date, value: provisional) in occurrences.entries) {
      final id = chargeMovementId(s.id, date);
      if (settings.deletedChargeIds.contains(id)) continue;
      final current = byId[id];
      if (current == null) {
        // Si sustituye a un provisional editado a mano, hereda su importe y nota.
        final edited = superseded
            .where((m) => m.userEdited && !m.date.isAfter(date.add(const Duration(days: 20))))
            .firstOrNull;
        upsert.add(Movement(
          id: id,
          kind: MovementKind.expense,
          amount: edited?.amount ?? s.price,
          categoryId: kSubscriptionsCategoryId,
          date: date,
          title: s.name,
          note: edited?.note ?? '',
          origin: MovementOrigin.subscription,
          subscriptionId: s.id,
          provisional: provisional,
          userEdited: edited != null,
          createdAt: now,
        ));
        if (edited != null) superseded.remove(edited);
        continue;
      }
      // Solo un cobro aún previsto sigue el precio actual; uno confirmado o
      // editado a mano conserva su importe.
      final followPrice = current.provisional && provisional && !current.userEdited;
      final desired = followPrice
          ? current.copyWith(provisional: provisional, amount: s.price, title: s.name)
          : current.copyWith(provisional: provisional);
      if (!_same(desired, current)) upsert.add(desired);
    }
  }
  return (upsert: upsert, delete: delete);
}

bool _same(Movement a, Movement b) => a.toJson().toString() == b.toJson().toString();
