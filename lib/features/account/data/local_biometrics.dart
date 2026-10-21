import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../domain/auth_service.dart';

/// Face ID / Touch ID con local_auth. No es "solo biometría": si la cara no
/// se reconoce, iOS ofrece el código del iPhone.
class LocalBiometrics implements Biometrics {
  LocalBiometrics([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported() && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String> label() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return 'Face ID';
      if (types.contains(BiometricType.fingerprint)) {
        return defaultTargetPlatform == TargetPlatform.iOS ? 'Touch ID' : 'Huella';
      }
    } on PlatformException {
      // Sin biometría: etiqueta genérica.
    }
    return 'Face ID';
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: false);
    } on LocalAuthException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
