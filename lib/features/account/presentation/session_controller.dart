import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/storage/local_store.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../data/auth_providers.dart';
import '../domain/account.dart';
import '../domain/auth_service.dart';

export '../data/auth_providers.dart';

sealed class SessionState {
  const SessionState();
}

class SessionLoading extends SessionState {
  const SessionLoading();
}

/// Sin cuenta: pantalla de bienvenida con "Continuar con Google".
class SignedOut extends SessionState {
  const SignedOut();
}

/// Con cuenta, bloqueada: Face ID (solo al pulsar) o "Continuar con Google".
class Locked extends SessionState {
  const Locked(this.account, {this.faceId = false, this.faceIdLabel = 'Face ID'});
  final Account account;

  /// Se ofrece el botón de Face ID (activado en ajustes y disponible).
  final bool faceId;
  final String faceIdLabel;
}

/// Con cuenta, falta la configuración inicial ([short] para quien ya tenía datos).
class NeedsOnboarding extends SessionState {
  const NeedsOnboarding(this.account, {required this.short});
  final Account account;
  final bool short;
}

class Ready extends SessionState {
  const Ready(this.account);
  final Account account;
}

/// Cuenta con la que se está usando la app (null fuera de sesión).
final currentAccountProvider = Provider<Account?>((ref) => switch (ref.watch(sessionControllerProvider)) {
      Ready(:final account) || Locked(:final account) || NeedsOnboarding(:final account) => account,
      _ => null,
    });

/// Ya había suscripciones guardadas (usuario que actualiza desde la versión con PIN).
final hasExistingDataProvider = Provider<bool>(
  (ref) => ref.watch(localStoreProvider).readAll(LocalStore.subscriptionsBox).isNotEmpty,
);

/// Borra las claves del PIN de la versión anterior.
final clearLegacyPinProvider = Provider<Future<void> Function()>((ref) {
  final secure = ref.watch(secureStorageProvider);
  return () async {
    for (final k in const [
      'auth.pin.hash',
      'auth.pin.salt',
      'auth.pin.fails',
      'auth.pin.lockedUntil',
      'auth.biometrics',
    ]) {
      await secure.delete(key: k);
    }
  };
});

final sessionControllerProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

class SessionController extends Notifier<SessionState> {
  AuthService get _auth => ref.read(authServiceProvider);
  Biometrics get _bio => ref.read(biometricsProvider);

  bool _bioAvailable = false;
  String _bioLabel = 'Face ID';

  @override
  SessionState build() {
    Future.microtask(_load);
    return const SessionLoading();
  }

  Future<void> _load() async {
    try {
      await ref.read(clearLegacyPinProvider)();
    } catch (_) {
      // Un llavero inaccesible no debe impedir entrar.
    }
    _bioAvailable = await _bio.isAvailable();
    if (_bioAvailable) _bioLabel = await _bio.label();
    final account = _auth.current;
    if (account != null) {
      // La cuenta con sesión al actualizar pasa a ser la dueña de la wallet.
      final repo = ref.read(walletSettingsRepositoryProvider);
      if (repo.read().ownerUid == null) await repo.save(repo.read().copyWith(ownerUid: account.uid));
    }
    state = account == null ? const SignedOut() : _after(account, lock: true);
  }

  SessionState _after(Account account, {required bool lock}) {
    final settings = ref.read(walletSettingsRepositoryProvider).read();
    if (!settings.onboardingDone) {
      return NeedsOnboarding(account, short: ref.read(hasExistingDataProvider));
    }
    if (!lock) return Ready(account);
    return Locked(account, faceId: settings.faceIdEnabled && _bioAvailable, faceIdLabel: _bioLabel);
  }

  /// "Continuar con Google". Devuelve el mensaje a mostrar si falla
  /// (null si salió bien o el usuario cerró el selector).
  Future<String?> continueWithGoogle() async {
    final s = state;
    // La cuenta de vista previa no prueba quién es: para desbloquear se pide
    // Face ID o el código del iPhone (si el dispositivo lo tiene).
    if (s is Locked && !_auth.verifiesIdentity) {
      if (_bioAvailable && !await _bio.authenticate('Desbloquea Outflow para ver tu wallet')) return null;
      if (state is Locked) state = Ready(s.account);
      return null;
    }
    try {
      final account = await _auth.signInWithGoogle();
      final repo = ref.read(walletSettingsRepositoryProvider);
      final owner = repo.read().ownerUid ?? (s is Locked ? s.account.uid : null);
      if (owner != null && owner != account.uid) {
        // Otra cuenta no abre esta wallet.
        await _auth.signOut();
        return 'Esa no es la cuenta de esta wallet.';
      }
      if (owner == null) await repo.save(repo.read().copyWith(ownerUid: account.uid));
      state = _after(account, lock: false);
      return null;
    } on AuthOffline {
      return 'Sin conexión';
    } on AuthCancelled {
      return null;
    } on AuthFailed catch (e) {
      return e.message;
    }
  }

  /// Solo se llama al pulsar el botón: nunca automáticamente.
  Future<bool> unlockWithFaceId() async {
    final s = state;
    if (s is! Locked) return false;
    final ok = await _bio.authenticate('Desbloquea Outflow para ver tu wallet');
    if (ok && state is Locked) state = Ready(s.account);
    return ok;
  }

  void lock() {
    final s = state;
    if (s is Ready) state = _after(s.account, lock: true);
  }

  Future<void> finishOnboarding() async {
    final s = state;
    if (s is NeedsOnboarding) state = _after(s.account, lock: false);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    state = const SignedOut();
  }

  /// Face ID disponible en el dispositivo (para el paso de configuración y Ajustes).
  bool get biometricsAvailable => _bioAvailable;
  String get biometricsLabel => _bioLabel;
}
