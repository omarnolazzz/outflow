import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../data/hive_subscription_repository.dart';
import '../../notifications/domain/charge_answer.dart';
import '../domain/apply_charge_answer.dart';
import '../domain/charge_pattern.dart';
import '../domain/dashboard_summary.dart';
import '../domain/entities/subscription.dart';
import '../domain/subscription_repository.dart';

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => HiveSubscriptionRepository(ref.watch(localStoreProvider)),
);

final subscriptionsProvider = StreamProvider<List<Subscription>>(
  (ref) => ref.watch(subscriptionRepositoryProvider).watchAll(),
);

final subscriptionByIdProvider = Provider.family<Subscription?, String>((ref, id) {
  final list = ref.watch(subscriptionsProvider).value ?? const [];
  for (final s in list) {
    if (s.id == id) return s;
  }
  return null;
});

final dashboardSummaryProvider = Provider<AsyncValue<DashboardSummary>>((ref) {
  final now = ref.watch(nowProvider);
  return ref.watch(subscriptionsProvider).whenData((subs) => DashboardSummary.compute(subs, now));
});

/// Comandos sobre suscripciones (la UI nunca toca el repositorio directamente).
final subscriptionActionsProvider = Provider<SubscriptionActions>(
  (ref) => SubscriptionActions(ref.watch(subscriptionRepositoryProvider)),
);

class SubscriptionActions {
  SubscriptionActions(this._repo);
  final SubscriptionRepository _repo;

  Future<void> save(Subscription s) => _repo.save(s);

  Future<void> delete(String id) => _repo.delete(id);

  /// Respuesta a la pregunta del cobro (botón de notificación). Las obsoletas se ignoran.
  Future<void> applyAnswer(ChargeAnswer answer) async {
    final s = await _repo.byId(answer.subscriptionId);
    final updated = s == null ? null : applyChargeAnswer(s, answer, DateTime.now());
    if (updated != null) await _repo.save(updated);
  }

  /// Respuesta detallada desde la app. Devuelve la versión anterior para deshacer.
  Future<Subscription> confirmCharge(
    Subscription s, {
    required DateTime pending,
    required DateTime chargedOn,
    required DateTime next,
    ChargePattern? pattern,
  }) async {
    await _repo.save(s.confirmCharge(pending: pending, chargedOn: chargedOn, next: next, pattern: pattern));
    return s;
  }

  /// Cambia el estado y devuelve el anterior para poder deshacer.
  Future<Subscription> setStatus(Subscription s, SubscriptionStatus status) async {
    await _repo.save(s.copyWith(status: status, statusChangedAt: DateTime.now()));
    return s;
  }
}
