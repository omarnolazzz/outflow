import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../data/secure_auth_repository.dart';
import '../domain/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SecureAuthRepository(ref.watch(secureStorageProvider)),
);

final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>(
  (ref) => LocalBiometricAuthenticator(),
);

sealed class AppLockState {
  const AppLockState();
}

class LockLoading extends AppLockState {
  const LockLoading();
}

/// Primera apertura: hay que crear el PIN.
class LockNeedsSetup extends AppLockState {
  const LockNeedsSetup({this.biometricLabel});
  final String? biometricLabel;
}

class LockLocked extends AppLockState {
  const LockLocked({this.biometricLabel, this.lockedOutUntil});

  /// No nulo si la biometría está activada y disponible.
  final String? biometricLabel;
  final DateTime? lockedOutUntil;
}

class LockUnlocked extends AppLockState {
  const LockUnlocked();
}

final lockControllerProvider = NotifierProvider<LockController, AppLockState>(LockController.new);

class LockController extends Notifier<AppLockState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);
  BiometricAuthenticator get _bio => ref.read(biometricAuthenticatorProvider);

  @override
  AppLockState build() {
    Future.microtask(_load);
    return const LockLoading();
  }

  Future<String?> _availableBiometric() async =>
      await _bio.isAvailable() ? await _bio.label() : null;

  Future<void> _load() async {
    if (!await _repo.hasPin()) {
      state = LockNeedsSetup(biometricLabel: await _availableBiometric());
      return;
    }
    await lock();
  }

  Future<void> lock() async {
    if (!await _repo.hasPin()) return;
    final label = await _repo.biometricsEnabled() ? await _availableBiometric() : null;
    state = LockLocked(biometricLabel: label, lockedOutUntil: await _repo.lockedOutUntil());
  }

  Future<void> createPin(String pin, {required bool enableBiometrics}) async {
    await _repo.setPin(pin);
    await _repo.setBiometricsEnabled(enableBiometrics);
    state = const LockUnlocked();
  }

  Future<PinCheck> submitPin(String pin) async {
    final result = await _repo.verifyPin(pin);
    switch (result) {
      case PinAccepted():
        state = const LockUnlocked();
      case PinLockedOut(:final until):
        final current = state;
        state = LockLocked(
          biometricLabel: current is LockLocked ? current.biometricLabel : null,
          lockedOutUntil: until,
        );
      case PinRejected():
        break;
    }
    return result;
  }

  Future<bool> unlockWithBiometrics() async {
    final ok = await _bio.authenticate('Desbloquea Outflow para ver tus pagos');
    if (ok) state = const LockUnlocked();
    return ok;
  }

  Future<bool> biometricsEnabled() => _repo.biometricsEnabled();

  Future<void> setBiometricsEnabled(bool enabled) => _repo.setBiometricsEnabled(enabled);

  Future<String?> availableBiometric() => _availableBiometric();
}
