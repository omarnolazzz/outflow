import '../../../core/storage/local_store.dart';
import '../domain/category.dart';
import '../domain/default_categories.dart';

abstract interface class CategoryRepository {
  Stream<List<Category>> watchAll();
  Future<void> save(Category category);
  Future<void> delete(String id);
}

class HiveCategoryRepository implements CategoryRepository {
  HiveCategoryRepository(this._store);

  final LocalStore _store;
  static const _box = LocalStore.categoriesBox;

  /// Siembra las categorías por defecto la primera vez.
  Future<void> _seed() async {
    if (_store.readAll(_box).isNotEmpty) return;
    await _store.writeAll(_box, {for (final c in defaultCategories()) c.id: c.toJson()});
  }

  @override
  Stream<List<Category>> watchAll() async* {
    await _seed();
    // Orden estable: el de la lista por defecto y luego las propias.
    final order = {for (final (i, c) in defaultCategories().indexed) c.id: i};
    yield* _store.watchAll(_box).map((rows) {
      final list = rows.map(Category.fromJson).toList()
        ..sort((a, b) => (order[a.id] ?? 1 << 20).compareTo(order[b.id] ?? 1 << 20));
      return list;
    });
  }

  @override
  Future<void> save(Category category) => _store.write(_box, category.id, category.toJson());

  @override
  Future<void> delete(String id) async {
    if (id == kSubscriptionsCategoryId) return;
    await _store.remove(_box, id);
  }
}
