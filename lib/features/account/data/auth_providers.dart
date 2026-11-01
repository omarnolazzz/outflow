import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/di/core_providers.dart';
import '../domain/auth_service.dart';
import 'firebase_auth_service.dart';
import 'local_biometrics.dart';
import 'preview_auth_service.dart';

/// Google real en el iPhone con Firebase configurado; cuenta simulada en la
/// vista previa web o si la build no trae la configuración.
final authServiceProvider = Provider<AuthService>((ref) {
  if (kIsWeb || !FirebaseConfig.usable) return PreviewAuthService(ref.watch(localStoreProvider));
  return FirebaseAuthService();
});

final biometricsProvider = Provider<Biometrics>((ref) => LocalBiometrics());
