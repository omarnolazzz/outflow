import 'package:firebase_core/firebase_core.dart';

/// Configuración de Firebase / Google Sign-In inyectada al compilar con
/// `--dart-define` (los valores salen de `GoogleService-Info.plist`). Así el
/// repositorio no lleva el archivo y la vista previa web funciona sin ellos.
abstract final class FirebaseConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  /// CLIENT_ID del plist (cliente OAuth de iOS).
  static const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  static bool get isConfigured =>
      apiKey.isNotEmpty && appId.isNotEmpty && senderId.isNotEmpty && projectId.isNotEmpty && iosClientId.isNotEmpty;

  static FirebaseOptions get options => const FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: senderId,
        projectId: projectId,
        iosClientId: iosClientId,
        iosBundleId: 'com.gabrielnolazco.outflow',
      );
}
