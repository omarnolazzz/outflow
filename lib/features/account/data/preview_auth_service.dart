import '../../../core/storage/local_store.dart';
import '../domain/account.dart';
import '../domain/auth_service.dart';

/// Cuenta simulada para la vista previa web y para builds sin Firebase
/// configurado: "Continuar con Google" entra con una cuenta de ejemplo.
class PreviewAuthService implements AuthService {
  PreviewAuthService(this._store);

  final LocalStore _store;
  static const _id = 'account.preview';

  static const _demo = Account(uid: 'preview', email: 'vista.previa@outflow.app', displayName: 'Vista previa');

  @override
  Account? get current => _store.read(LocalStore.settingsBox, _id) == null ? null : _demo;

  @override
  Future<Account> signInWithGoogle() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await _store.write(LocalStore.settingsBox, _id, const {'signedIn': true});
    return _demo;
  }

  @override
  Future<void> signOut() => _store.remove(LocalStore.settingsBox, _id);
}
