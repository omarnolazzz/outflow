import '../../../core/storage/local_store.dart';
import '../domain/movement.dart';

abstract interface class MovementRepository {
  /// Emite la lista completa al suscribirse y en cada cambio.
  Stream<List<Movement>> watchAll();
  Future<void> save(Movement movement);
  Future<void> saveAll(Iterable<Movement> movements);
  Future<void> delete(String id);
  Future<void> deleteAll(Iterable<String> ids);
}

class HiveMovementRepository implements MovementRepository {
  HiveMovementRepository(this._store);

  final LocalStore _store;
  static const _box = LocalStore.movementsBox;

  @override
  Stream<List<Movement>> watchAll() =>
      _store.watchAll(_box).map((rows) => rows.map(Movement.fromJson).toList());

  @override
  Future<void> save(Movement movement) => _store.write(_box, movement.id, movement.toJson());

  @override
  Future<void> saveAll(Iterable<Movement> movements) =>
      _store.writeAll(_box, {for (final m in movements) m.id: m.toJson()});

  @override
  Future<void> delete(String id) => _store.remove(_box, id);

  @override
  Future<void> deleteAll(Iterable<String> ids) => _store.removeAll(_box, ids);
}
