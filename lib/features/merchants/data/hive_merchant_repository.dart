import '../../../core/storage/local_store.dart';
import '../domain/entities/merchant.dart';
import '../domain/merchant_repository.dart';
import 'merchant_catalog.dart';

/// Modelo de persistencia para comercios personalizados.
abstract final class MerchantModel {
  static Map<String, Object?> toJson(Merchant m) => {
        'v': 1,
        'id': m.id,
        'name': m.name,
        'category': m.category.name,
        'logo': m.logo.toJson(),
        'billing': m.billing.toJson(),
      };

  static Merchant fromJson(Map<String, Object?> json) => Merchant(
        id: json['id'] as String,
        name: json['name'] as String,
        category: SpendCategory.values.asNameMap()[json['category']] ?? SpendCategory.other,
        logo: MerchantLogo.fromJson((json['logo'] as Map).cast()),
        billing: BillingDefaults.fromJson((json['billing'] as Map).cast()),
        isCustom: true,
      );
}

class HiveMerchantRepository implements MerchantRepository {
  HiveMerchantRepository(this._store);

  final LocalStore _store;
  static const _box = LocalStore.merchantsBox;

  @override
  Stream<List<Merchant>> watchAll() => _store.watchAll(_box).map(
        (rows) => [...rows.map(MerchantModel.fromJson), ...MerchantCatalog.all],
      );

  @override
  Future<void> saveCustom(Merchant merchant) {
    assert(merchant.isCustom);
    return _store.write(_box, merchant.id, MerchantModel.toJson(merchant));
  }

  @override
  Future<void> deleteCustom(String id) => _store.remove(_box, id);
}
