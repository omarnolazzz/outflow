import 'entities/merchant.dart';

abstract interface class MerchantRepository {
  /// Catálogo predefinido + comercios personalizados del usuario.
  Stream<List<Merchant>> watchAll();
  Future<void> saveCustom(Merchant merchant);
  Future<void> deleteCustom(String id);
}
