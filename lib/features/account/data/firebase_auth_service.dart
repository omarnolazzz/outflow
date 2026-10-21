import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/firebase_config.dart';
import '../domain/account.dart';
import '../domain/auth_service.dart';

/// "Continuar con Google" con Firebase Authentication.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({FirebaseAuth? auth, GoogleSignIn? google})
      : _auth = auth ?? FirebaseAuth.instance,
        _google = google ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _google;
  Future<void>? _init;

  Future<void> _ensureInit() => _init ??= _google.initialize(clientId: FirebaseConfig.iosClientId);

  static Account _toAccount(User u) => Account(
        uid: u.uid,
        email: u.email ?? '',
        displayName: u.displayName ?? '',
        photoUrl: u.photoURL,
      );

  @override
  Account? get current {
    final u = _auth.currentUser;
    return u == null ? null : _toAccount(u);
  }

  @override
  Future<Account> signInWithGoogle() async {
    try {
      await _ensureInit();
      final google = await _google.authenticate();
      final idToken = google.authentication.idToken;
      if (idToken == null) throw const AuthFailed('Google no devolvió credenciales.');
      final result = await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      return _toAccount(result.user!);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) {
        throw const AuthCancelled();
      }
      throw AuthFailed('No se pudo iniciar sesión con Google (${e.code.name}).');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') throw const AuthOffline();
      throw AuthFailed('No se pudo iniciar sesión (${e.code}).');
    }
  }

  @override
  Future<void> signOut() async {
    await _ensureInit();
    await _google.signOut();
    await _auth.signOut();
  }
}
