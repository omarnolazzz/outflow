import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/storage/local_store.dart';
import '../../capture/data/capture_inbox.dart';
import '../../friends/presentation/friends_providers.dart';
import '../../notifications/data/charge_answer_inbox.dart';
import '../../wallet/domain/default_categories.dart';
import '../../wallet/domain/wallet_settings.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../data/auth_providers.dart';
import '../data/device_session.dart';
import '../data/preview_auth_service.dart';
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
  const SignedOut({this.notice});

  /// Aviso para la bienvenida (p. ej. la cuenta se abrió en otro dispositivo).
  final String? notice;
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

/// Vigila que este dispositivo siga siendo el de la cuenta (se observa en
/// `app.dart`). Si el documento no existe (usuario que actualiza) lo reclama;
/// si otro dispositivo confirmado por el servidor lo tiene, cierra la sesión.
final deviceSessionGuardProvider = Provider<void>((ref) {
  final uid = ref.watch(currentAccountProvider.select((a) => a?.uid));
  final deviceId = ref.watch(deviceIdProvider).value;
  if (uid == null || deviceId == null || !ref.watch(authServiceProvider).verifiesIdentity) return;
  final repo = ref.watch(deviceSessionRepositoryProvider);
  var claimed = false;
  final sub = repo.watch(uid).listen(
    (remote) {
      if (isSessionLost(remote, deviceId)) {
        ref.read(sessionControllerProvider.notifier).sessionLost();
      } else if (remote.deviceId == null && remote.trusted && !claimed) {
        claimed = true;
        repo.claim(uid, deviceId).catchError((Object e) {
          debugPrint('No se pudo reclamar la sesión: $e');
        });
      }
    },
    onError: (Object e) => debugPrint('No se pudo vigilar la sesión: $e'),
  );
  ref.onDispose(sub.cancel);
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
      final saved = repo.read().ownerUid;
      // Una wallet empezada con la cuenta de vista previa pasa a la primera
      // cuenta real de Google con la que se entre.
      final owner = saved == PreviewAuthService.uid && _auth.verifiesIdentity
          ? null
          : saved ?? (s is Locked ? s.account.uid : null);
      if (owner != null && owner != account.uid) {
        // Otra cuenta no abre esta wallet.
        await _auth.signOut();
        return 'Esa no es la cuenta de esta wallet.';
      }
      if (owner == null && saved != account.uid) await repo.save(repo.read().copyWith(ownerUid: account.uid));
      // El último dispositivo en entrar se queda con la cuenta. Sin esperar al
      // servidor: sin red la escritura no termina hasta que vuelve.
      await _claimDevice(account);
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

  /// Lanza el `claim` sin esperar al servidor. Se llama antes de pasar a la
  /// sesión abierta para que la escritura ya esté pendiente cuando el guard
  /// empiece a vigilar (si no, vería el documento viejo del otro dispositivo).
  Future<void> _claimDevice(Account account) async {
    try {
      final deviceId = await ref.read(deviceIdProvider.future);
      unawaited(ref.read(deviceSessionRepositoryProvider).claim(account.uid, deviceId).catchError((Object e) {
        debugPrint('No se pudo reclamar la sesión: $e');
      }));
    } catch (e) {
      debugPrint('No se pudo reclamar la sesión: $e');
    }
  }

  /// Otro dispositivo abrió la cuenta: se cierra la sesión aquí, pero la
  /// wallet local y su dueña (`ownerUid`) quedan como estaban.
  Future<void> sessionLost() async {
    await _auth.signOut();
    state = const SignedOut(notice: 'Tu cuenta se abrió en otro dispositivo.');
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

  /// "Borrar toda la información": deja la cuenta como recién creada. Vacía
  /// el teléfono (gastos, suscripciones, categorías propias, cuentas, ajustes),
  /// borra lo compartido que es tuyo en la nube y vuelve a la configuración
  /// inicial con la misma cuenta de Google y solo "Mi cuenta".
  Future<void> eraseEverything() async {
    final account = switch (state) {
      Ready(:final account) || Locked(:final account) || NeedsOnboarding(:final account) => account,
      _ => null,
    };
    if (account == null) return;
    // Lo de la nube no espera al servidor: sin red se completa al volver.
    unawaited(ref.read(socialRepositoryProvider).forgetMe().catchError((Object e) {
      debugPrint('No se pudo borrar lo compartido: $e');
    }));
    final store = ref.read(localStoreProvider);
    await store.clearAll();
    await store.writeAll(LocalStore.categoriesBox, {for (final c in defaultCategories()) c.id: c.toJson()});
    final fresh = WalletSettings(ownerUid: account.uid);
    await ref.read(walletSettingsRepositoryProvider).save(fresh);
    await ref.read(accountRepositoryProvider).ensureDefault(fresh.currency);
    try {
      await const ChargeAnswerInbox().drain();
    } catch (_) {
      // Sin respuestas pendientes que descartar.
    }
    try {
      await ref.read(captureInboxProvider).clear();
    } catch (_) {
      // Sin textos pendientes que descartar.
    }
    state = NeedsOnboarding(account, short: false);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    state = const SignedOut();
  }

  /// Face ID disponible en el dispositivo (para el paso de configuración y Ajustes).
  bool get biometricsAvailable => _bioAvailable;
  String get biometricsLabel => _bioLabel;
}
