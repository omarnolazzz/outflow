import 'account.dart';

/// Fallo al iniciar sesión.
sealed class AuthException implements Exception {
  const AuthException();
}

/// Sin conexión.
class AuthOffline extends AuthException {
  const AuthOffline();
}

/// El usuario cerró el selector de cuentas.
class AuthCancelled extends AuthException {
  const AuthCancelled();
}

class AuthFailed extends AuthException {
  const AuthFailed(this.message);
  final String message;
}

abstract interface class AuthService {
  /// Sesión guardada en el dispositivo (null si no hay).
  Account? get current;

  /// false en la cuenta de vista previa: no prueba quién es el usuario.
  bool get verifiesIdentity;

  /// "Continuar con Google". Lanza [AuthException].
  Future<Account> signInWithGoogle();
  Future<void> signOut();
}

/// Face ID / Touch ID (con el código del iPhone como respaldo del sistema).
abstract interface class Biometrics {
  Future<bool> isAvailable();

  /// "Face ID", "Touch ID"…
  Future<String> label();
  Future<bool> authenticate(String reason);
}
