import '../../../core/storage/local_store.dart';
import '../domain/entities/subscription.dart';
import '../domain/subscription_repository.dart';
import 'subscription_model.dart';

class HiveSubscriptionRepository implements SubscriptionRepository {
  HiveSubscriptionRepository(this._store);

  final LocalStore _store;
  static const _box = LocalStore.subscriptionsBox;

  @override
  Stream<List<Subscription>> watchAll() =>
      _store.watchAll(_box).map((rows) => rows.map(SubscriptionModel.fromJson).toList());

  @override
  Future<Subscription?> byId(String id) async {
    final json = _store.read(_box, id);
    return json == null ? null : SubscriptionModel.fromJson(json);
  }

  @override
  Future<void> save(Subscription subscription) =>
      _store.write(_box, subscription.id, SubscriptionModel.toJson(subscription));

  @override
  Future<void> delete(String id) => _store.remove(_box, id);
}
