import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../domain/auth_repository.dart';

/// PIN guardado como PBKDF2-HMAC-SHA256 con sal aleatoria en el
/// Keychain (iOS) / Keystore (Android). El PIN nunca se guarda en claro.
class SecureAuthRepository implements AuthRepository {
  SecureAuthRepository(this._secure);

  final FlutterSecureStorage _secure;

  static const _hashKey = 'auth.pin.hash';
  static const _saltKey = 'auth.pin.salt';
  static const _failsKey = 'auth.pin.fails';
  static const _lockKey = 'auth.pin.lockedUntil';
  static const _bioKey = 'auth.biometrics';

  static const _iterations = 60000;
  static const _maxAttempts = 5;

  @override
  Future<bool> hasPin() async => await _secure.read(key: _hashKey) != null;

  @override
  Future<void> setPin(String pin) async {
    final salt = _randomBytes(16);
    final hash = await Isolate.run(() => _pbkdf2(pin, salt));
    await _secure.write(key: _saltKey, value: base64Encode(salt));
    await _secure.write(key: _hashKey, value: base64Encode(hash));
    await _secure.delete(key: _failsKey);
    await _secure.delete(key: _lockKey);
  }

  @override
  Future<DateTime?> lockedOutUntil() async {
    final raw = await _secure.read(key: _lockKey);
    final until = raw == null ? null : DateTime.tryParse(raw);
    return until != null && until.isAfter(DateTime.now()) ? until : null;
  }

  @override
  Future<PinCheck> verifyPin(String pin) async {
    final locked = await lockedOutUntil();
    if (locked != null) return PinLockedOut(locked);

    final salt = base64Decode((await _secure.read(key: _saltKey))!);
    final expected = base64Decode((await _secure.read(key: _hashKey))!);
    final actual = await Isolate.run(() => _pbkdf2(pin, salt));

    if (_constantTimeEquals(actual, expected)) {
      await _secure.delete(key: _failsKey);
      return const PinAccepted();
    }

    final fails = int.parse(await _secure.read(key: _failsKey) ?? '0') + 1;
    await _secure.write(key: _failsKey, value: '$fails');
    if (fails % _maxAttempts == 0) {
      // 30 s, 60 s, 120 s… cada 5 fallos.
      final seconds = 30 * pow(2, fails ~/ _maxAttempts - 1).toInt();
      final until = DateTime.now().add(Duration(seconds: seconds));
      await _secure.write(key: _lockKey, value: until.toIso8601String());
      return PinLockedOut(until);
    }
    return PinRejected(attemptsLeft: _maxAttempts - fails % _maxAttempts);
  }

  @override
  Future<bool> biometricsEnabled() async => await _secure.read(key: _bioKey) == '1';

  @override
  Future<void> setBiometricsEnabled(bool enabled) =>
      _secure.write(key: _bioKey, value: enabled ? '1' : '0');

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  /// PBKDF2 con un solo bloque (salida de 32 bytes = tamaño de SHA-256).
  static List<int> _pbkdf2(String pin, List<int> salt) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final out = List<int>.from(u);
    for (var i = 1; i < _iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return out;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class LocalBiometricAuthenticator implements BiometricAuthenticator {
  LocalBiometricAuthenticator([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String> label() async {
    final types = await _auth.getAvailableBiometrics();
    if (types.contains(BiometricType.face)) return 'Face ID';
    if (types.contains(BiometricType.fingerprint)) {
      return defaultTargetPlatform == TargetPlatform.iOS ? 'Touch ID' : 'Huella';
    }
    return 'Biometría';
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true);
    } on LocalAuthException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
