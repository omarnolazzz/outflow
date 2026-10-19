sealed class PinCheck {
  const PinCheck();
}

class PinAccepted extends PinCheck {
  const PinAccepted();
}

class PinRejected extends PinCheck {
  const PinRejected({required this.attemptsLeft});
  final int attemptsLeft;
}

/// Demasiados intentos: bloqueo temporal creciente.
class PinLockedOut extends PinCheck {
  const PinLockedOut(this.until);
  final DateTime until;
}

abstract interface class AuthRepository {
  Future<bool> hasPin();
  Future<void> setPin(String pin);
  Future<PinCheck> verifyPin(String pin);

  /// Bloqueo vigente (si lo hay), para mostrarlo al abrir la app.
  Future<DateTime?> lockedOutUntil();

  Future<bool> biometricsEnabled();
  Future<void> setBiometricsEnabled(bool enabled);
}

abstract interface class BiometricAuthenticator {
  /// true si el dispositivo tiene biometría o credencial del sistema disponible.
  Future<bool> isAvailable();

  /// "Face ID", "Touch ID", "huella"… para rotular el botón.
  Future<String> label();

  Future<bool> authenticate(String reason);
}
