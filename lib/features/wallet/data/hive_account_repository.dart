import '../../../core/storage/local_store.dart';
import '../domain/wallet_account.dart';

abstract interface class AccountRepository {
  Stream<List<WalletAccount>> watchAll();

  /// La cuenta por defecto no se puede archivar: se guarda sin archivar.
  Future<void> save(WalletAccount account);

  /// Una cuenta con movimientos no se borra: se archiva. La cuenta por defecto
  /// no se borra nunca.
  Future<void> delete(String id);

  /// Crea "Mi cuenta" solo si no hay ninguna y devuelve la cuenta por defecto.
  /// Es idempotente, también con llamadas simultáneas.
  Future<WalletAccount> ensureDefault(String currency);
}

class HiveAccountRepository implements AccountRepository {
  HiveAccountRepository(this._store);

  final LocalStore _store;
  static const _box = LocalStore.accountsBox;

  List<WalletAccount> _all() => _store.readAll(_box).map(WalletAccount.fromJson).toList();

  @override
  Stream<List<WalletAccount>> watchAll() =>
      _store.watchAll(_box).map((rows) => sortAccounts(rows.map(WalletAccount.fromJson)));

  @override
  Future<void> save(WalletAccount account) {
    final a = account.isDefault && account.archived ? account.copyWith(archived: false) : account;
    return _store.write(_box, a.id, a.toJson());
  }

  @override
  Future<void> delete(String id) async {
    final doc = _store.read(_box, id);
    if (doc == null) return;
    final account = WalletAccount.fromJson(doc);
    if (account.isDefault) return;
    final used = _store
        .readAll(LocalStore.movementsBox)
        .any((m) => m['accountId'] == id || m['toAccountId'] == id);
    if (used) {
      await _store.write(_box, id, account.copyWith(archived: true).toJson());
    } else {
      await _store.remove(_box, id);
    }
  }

  @override
  Future<WalletAccount> ensureDefault(String currency) async {
    final current = defaultAccountOf(_all());
    if (current != null) return current;
    // Id fijo: si dos llamadas llegan aquí, escriben el mismo documento.
    final account = newDefaultAccount(currency, DateTime.now());
    await _store.write(_box, account.id, account.toJson());
    return account;
  }
}
