import 'entities/subscription.dart';

abstract interface class SubscriptionRepository {
  /// Emite la lista completa al suscribirse y en cada cambio.
  Stream<List<Subscription>> watchAll();
  Future<Subscription?> byId(String id);
  Future<void> save(Subscription subscription);
  Future<void> delete(String id);
}
