import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Configuración de Firebase / Google Sign-In inyectada al compilar con
/// `--dart-define` (valores de la consola de Firebase). Así el repositorio no
/// lleva archivos de configuración y la vista previa web funciona sin ellos.
abstract final class FirebaseConfig {
  // Comunes.
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  /// Cliente OAuth "web" que Firebase crea al activar Google: Android lo
  /// necesita para obtener el token de Google.
  static const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  // iPhone (GoogleService-Info.plist).
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  // Android (google-services.json).
  static const androidApiKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
  static const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isConfigured {
    final common = senderId.isNotEmpty && projectId.isNotEmpty;
    if (_android) return common && androidApiKey.isNotEmpty && androidAppId.isNotEmpty && webClientId.isNotEmpty;
    return common && apiKey.isNotEmpty && appId.isNotEmpty && iosClientId.isNotEmpty;
  }

  static FirebaseOptions get options => _android
      ? const FirebaseOptions(
          apiKey: androidApiKey,
          appId: androidAppId,
          messagingSenderId: senderId,
          projectId: projectId,
        )
      : const FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: senderId,
          projectId: projectId,
          iosClientId: iosClientId,
          iosBundleId: 'com.gabrielnolazco.outflow',
        );

  /// Para `GoogleSignIn.initialize`: en iPhone el cliente iOS; en Android
  /// basta el cliente web.
  static String? get googleClientId => _android ? null : iosClientId;
  static String? get googleServerClientId => webClientId.isEmpty ? null : webClientId;
}
