import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/domain/auth_service.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';

const gabriel = Account(uid: 'u1', email: 'g@example.com', displayName: 'Gabriel');

class FakeAuth implements AuthService {
  FakeAuth({this.current, this.failWith});
  @override
  Account? current;
  AuthException? failWith;
  int signIns = 0;

  @override
  Future<Account> signInWithGoogle() async {
    signIns++;
    if (failWith != null) throw failWith!;
    return current = gabriel;
  }

  @override
  Future<void> signOut() async => current = null;
}

class FakeBiometrics implements Biometrics {
  FakeBiometrics({this.result = true});
  bool result;
  int calls = 0;

  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<String> label() async => 'Face ID';
  @override
  Future<bool> authenticate(String reason) async {
    calls++;
    return result;
  }
}

void main() {
  late FakeAuth auth;
  late FakeBiometrics bio;
  late MemorySettings settings;
  late bool existingData;
  late int legacyCleared;

  setUp(() {
    auth = FakeAuth();
    bio = FakeBiometrics();
    settings = MemorySettings();
    existingData = false;
    legacyCleared = 0;
  });

  Future<ProviderContainer> start() async {
    final c = ProviderContainer(overrides: [
      authServiceProvider.overrideWithValue(auth),
      biometricsProvider.overrideWithValue(bio),
      walletSettingsRepositoryProvider.overrideWithValue(settings),
      hasExistingDataProvider.overrideWithValue(existingData),
      clearLegacyPinProvider.overrideWithValue(() async => legacyCleared++),
    ]);
    addTearDown(c.dispose);
    c.read(sessionControllerProvider);
    await pumpEventQueue();
    return c;
  }

  test('sin cuenta → SignedOut; Continuar con Google → configuración completa en instalación nueva', () async {
    final c = await start();
    expect(c.read(sessionControllerProvider), isA<SignedOut>());
    final error = await c.read(sessionControllerProvider.notifier).continueWithGoogle();
    expect(error, isNull);
    final s = c.read(sessionControllerProvider);
    expect(s, isA<NeedsOnboarding>());
    expect((s as NeedsOnboarding).short, isFalse);
    expect(s.account.email, 'g@example.com');
  });

  test('con cuenta y configuración hecha → Locked, y nunca pide Face ID sin que se pulse', () async {
    auth.current = gabriel;
    settings.value = const WalletSettings(onboardingDone: true, faceIdEnabled: true);
    final c = await start();
    final s = c.read(sessionControllerProvider);
    expect(s, isA<Locked>());
    expect((s as Locked).faceId, isTrue);
    expect(s.faceIdLabel, 'Face ID');
    expect(bio.calls, 0);
  });

  test('Face ID desactivado en ajustes → el botón no se ofrece', () async {
    auth.current = gabriel;
    settings.value = const WalletSettings(onboardingDone: true);
    final c = await start();
    expect((c.read(sessionControllerProvider) as Locked).faceId, isFalse);
  });

  test('Face ID correcto → Ready; fallido → sigue Locked', () async {
    auth.current = gabriel;
    settings.value = const WalletSettings(onboardingDone: true, faceIdEnabled: true);
    final c = await start();
    final ctrl = c.read(sessionControllerProvider.notifier);
    bio.result = false;
    expect(await ctrl.unlockWithFaceId(), isFalse);
    expect(c.read(sessionControllerProvider), isA<Locked>());
    bio.result = true;
    expect(await ctrl.unlockWithFaceId(), isTrue);
    expect(c.read(sessionControllerProvider), isA<Ready>());
  });

  test('Continuar con Google sin red devuelve "Sin conexión" y no cambia de estado', () async {
    auth.current = gabriel;
    settings.value = const WalletSettings(onboardingDone: true);
    final c = await start();
    auth.failWith = const AuthOffline();
    final error = await c.read(sessionControllerProvider.notifier).continueWithGoogle();
    expect(error, 'Sin conexión');
    expect(c.read(sessionControllerProvider), isA<Locked>());
  });

  test('cancelar el selector de Google no muestra error', () async {
    final c = await start();
    auth.failWith = const AuthCancelled();
    expect(await c.read(sessionControllerProvider.notifier).continueWithGoogle(), isNull);
    expect(c.read(sessionControllerProvider), isA<SignedOut>());
  });

  test('usuario con suscripciones y configuración pendiente → configuración corta', () async {
    existingData = true;
    auth.current = gabriel;
    final c = await start();
    final s = c.read(sessionControllerProvider);
    expect(s, isA<NeedsOnboarding>());
    expect((s as NeedsOnboarding).short, isTrue);
  });

  test('al arrancar se borra el PIN antiguo', () async {
    await start();
    expect(legacyCleared, 1);
  });

  test('lock() solo bloquea desde Ready; finishOnboarding entra a Ready', () async {
    auth.current = gabriel;
    final c = await start();
    final ctrl = c.read(sessionControllerProvider.notifier);
    ctrl.lock();
    expect(c.read(sessionControllerProvider), isA<NeedsOnboarding>());
    settings.value = const WalletSettings(onboardingDone: true);
    await ctrl.finishOnboarding();
    expect(c.read(sessionControllerProvider), isA<Ready>());
    ctrl.lock();
    expect(c.read(sessionControllerProvider), isA<Locked>());
  });

  test('cerrar sesión vuelve a SignedOut', () async {
    auth.current = gabriel;
    settings.value = const WalletSettings(onboardingDone: true);
    final c = await start();
    await c.read(sessionControllerProvider.notifier).signOut();
    expect(c.read(sessionControllerProvider), isA<SignedOut>());
    expect(auth.current, isNull);
  });
}
