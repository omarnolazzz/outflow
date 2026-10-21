import '../../../core/storage/local_store.dart';
import '../domain/wallet_settings.dart';

abstract interface class WalletSettingsRepository {
  Stream<WalletSettings> watch();
  WalletSettings read();
  Future<void> save(WalletSettings settings);
}

/// Guarda los ajustes de la wallet en la caja de ajustes.
class HiveWalletSettingsRepository implements WalletSettingsRepository {
  HiveWalletSettingsRepository(this._store);

  final LocalStore _store;
  static const _id = 'wallet.settings';

  @override
  WalletSettings read() {
    final json = _store.read(LocalStore.settingsBox, _id);
    return json == null ? const WalletSettings() : WalletSettings.fromJson(json);
  }

  @override
  Stream<WalletSettings> watch() => _store
      .watchAll(LocalStore.settingsBox)
      .map((_) => read())
      .distinct((a, b) => a.toJson().toString() == b.toJson().toString());

  @override
  Future<void> save(WalletSettings settings) =>
      _store.write(LocalStore.settingsBox, _id, settings.toJson());
}
