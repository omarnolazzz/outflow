import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/firebase_config.dart';
import '../domain/account.dart';
import '../domain/auth_service.dart';

/// "Continuar con Google" con Firebase Authentication.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({FirebaseAuth? auth, GoogleSignIn? google, Future<bool> Function()? online})
      : _authOverride = auth,
        _googleOverride = google,
        _online = online ?? _hasInternet;

  final FirebaseAuth? _authOverride;
  final GoogleSignIn? _googleOverride;
  final Future<bool> Function() _online;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  GoogleSignIn get _google => _googleOverride ?? GoogleSignIn.instance;

  /// Sin red, el selector de Google falla con errores poco claros: se comprueba antes.
  static Future<bool> _hasInternet() async {
    try {
      final r = await InternetAddress.lookup('accounts.google.com').timeout(const Duration(seconds: 4));
      return r.isNotEmpty;
    } on Object {
      return false;
    }
  }
  Future<void>? _init;

  Future<void> _ensureInit() => _init ??= _google.initialize(clientId: FirebaseConfig.iosClientId);

  static Account _toAccount(User u) => Account(
        uid: u.uid,
        email: u.email ?? '',
        displayName: u.displayName ?? '',
        photoUrl: u.photoURL,
      );

  @override
  bool get verifiesIdentity => true;

  @override
  Account? get current {
    final u = _auth.currentUser;
    return u == null ? null : _toAccount(u);
  }

  @override
  Future<Account> signInWithGoogle() async {
    if (!await _online()) throw const AuthOffline();
    try {
      await _ensureInit();
      final google = await _google.authenticate();
      final idToken = google.authentication.idToken;
      if (idToken == null) throw const AuthFailed('Google no devolvió credenciales.');
      final result = await _auth
          .signInWithCredential(GoogleAuthProvider.credential(idToken: idToken))
          .timeout(const Duration(seconds: 20));
      return _toAccount(result.user!);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) {
        throw const AuthCancelled();
      }
      throw AuthFailed('No se pudo iniciar sesión con Google (${e.code.name}).');
    } on TimeoutException {
      throw const AuthOffline();
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
