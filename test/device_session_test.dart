import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/account/data/device_session.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/account/presentation/welcome_screen.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'session_controller_test.dart' show FakeAuth, FakeBiometrics, gabriel;
import 'support/fakes.dart';

class FakeDeviceSessions implements DeviceSessionRepository {
  final claims = <(String, String)>[];
  final remote = StreamController<RemoteDevice>.broadcast();

  /// Si es true, `claim` nunca termina (sin red).
  bool hang = false;

  @override
  Future<void> claim(String uid, String deviceId) {
    claims.add((uid, deviceId));
    return hang ? Completer<void>().future : Future.value();
  }

  @override
  Stream<RemoteDevice> watch(String uid) => remote.stream;
}

void main() {
  group('isSessionLost', () {
    test('otro id y de confianza → perdida', () {
      expect(isSessionLost(const RemoteDevice(deviceId: 'otro', trusted: true), 'yo'), isTrue);
    });
    test('otro id sin confianza (caché o escritura pendiente) → no', () {
      expect(isSessionLost(const RemoteDevice(deviceId: 'otro', trusted: false), 'yo'), isFalse);
    });
    test('mismo id o sin documento → no', () {
      expect(isSessionLost(const RemoteDevice(deviceId: 'yo', trusted: true), 'yo'), isFalse);
      expect(isSessionLost(const RemoteDevice(deviceId: null, trusted: true), 'yo'), isFalse);
    });
  });

  group('sesión única', () {
    late FakeAuth auth;
    late FakeDeviceSessions sessions;
    late MemorySettings settings;
    late MemoryMovements movements;

    setUp(() {
      auth = FakeAuth();
      sessions = FakeDeviceSessions();
      settings = MemorySettings(const WalletSettings(onboardingDone: true, ownerUid: 'u1'));
      movements = MemoryMovements();
    });

    Future<ProviderContainer> start() async {
      final c = ProviderContainer(overrides: [
        authServiceProvider.overrideWithValue(auth),
        biometricsProvider.overrideWithValue(FakeBiometrics()),
        walletSettingsRepositoryProvider.overrideWithValue(settings),
        movementRepositoryProvider.overrideWithValue(movements),
        hasExistingDataProvider.overrideWithValue(false),
        clearLegacyPinProvider.overrideWithValue(() async {}),
        deviceSessionRepositoryProvider.overrideWithValue(sessions),
        deviceIdProvider.overrideWith((ref) async => 'yo'),
      ]);
      addTearDown(c.dispose);
      c.read(sessionControllerProvider);
      await pumpEventQueue();
      c.listen(deviceSessionGuardProvider, (_, _) {});
      await pumpEventQueue();
      return c;
    }

    test('sin documento (usuario que actualiza) reclama una sola vez', () async {
      auth.current = gabriel;
      final c = await start();
      sessions.remote.add(const RemoteDevice(deviceId: null, trusted: true));
      await pumpEventQueue();
      sessions.remote.add(const RemoteDevice(deviceId: null, trusted: true));
      await pumpEventQueue();
      expect(sessions.claims, [('u1', 'yo')]);
      expect(c.read(sessionControllerProvider), isA<Locked>());
    });

    test('documento ausente solo de caché no reclama', () async {
      auth.current = gabriel;
      await start();
      sessions.remote.add(const RemoteDevice(deviceId: null, trusted: false));
      await pumpEventQueue();
      expect(sessions.claims, isEmpty);
    });

    test('otro dispositivo → SignedOut con aviso, wallet intacta y misma dueña', () async {
      auth.current = gabriel;
      final c = await start();
      await movements.save(Movement(
        id: 'm1',
        kind: MovementKind.expense,
        amount: const Money(500, 'MXN'),
        categoryId: 'x',
        title: 'Café',
        date: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      ));
      sessions.remote.add(const RemoteDevice(deviceId: 'otro', trusted: true));
      await pumpEventQueue();
      final s = c.read(sessionControllerProvider);
      expect(s, isA<SignedOut>());
      expect((s as SignedOut).notice, 'Tu cuenta se abrió en otro dispositivo.');
      expect(auth.current, isNull);
      expect(movements.saved.length, 1);
      expect(settings.read().ownerUid, 'u1');
      expect(settings.read().onboardingDone, isTrue);
    });

    test('Continuar con Google reclama y entra aunque claim nunca termine', () async {
      sessions.hang = true;
      final c = await start();
      expect(c.read(sessionControllerProvider), isA<SignedOut>());
      final error = await c.read(sessionControllerProvider.notifier).continueWithGoogle();
      expect(error, isNull);
      expect(sessions.claims, [('u1', 'yo')]);
      expect(c.read(sessionControllerProvider), isA<Ready>());
    });

    test('desbloquear con Face ID no reclama', () async {
      auth.current = gabriel;
      settings.value = const WalletSettings(onboardingDone: true, faceIdEnabled: true, ownerUid: 'u1');
      final c = await start();
      expect(await c.read(sessionControllerProvider.notifier).unlockWithFaceId(), isTrue);
      expect(sessions.claims, isEmpty);
    });

    test('con la cuenta de vista previa no se vigila la sesión', () async {
      auth.current = gabriel;
      auth.verifiesIdentity = false;
      await start();
      sessions.remote.add(const RemoteDevice(deviceId: 'otro', trusted: true));
      await pumpEventQueue();
      expect(sessions.claims, isEmpty);
      expect(auth.current, isNotNull);
    });
  });

  testWidgets('la bienvenida muestra el aviso', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: WelcomeScreen(notice: 'Tu cuenta se abrió en otro dispositivo.')),
    ));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Tu cuenta se abrió en otro dispositivo.'), findsOneWidget);
  });
}
