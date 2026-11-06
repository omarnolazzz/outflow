import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/storage/local_store.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/capture/data/capture_inbox.dart';
import 'package:outflow/features/capture/presentation/capture_providers.dart';
import 'package:outflow/features/friends/presentation/friends_providers.dart';
import 'package:outflow/features/wallet/data/hive_movement_repository.dart';
import 'package:outflow/features/wallet/data/payment_listener.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'session_controller_test.dart' show FakeAuth, FakeBiometrics, gabriel;
import 'support/fakes.dart';

void main() {
  late Directory dir;
  late LocalStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('outflow_erase');
    Hive.init(dir.path);
    store = await LocalStore.openUnencrypted();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    dir.deleteSync(recursive: true);
  });

  test('borrar toda la información vacía el teléfono, olvida lo compartido y vuelve a la configuración', () async {
    await store.write(LocalStore.movementsBox, 'm1', {'id': 'm1'});
    await store.write(LocalStore.subscriptionsBox, 's1', {'id': 's1'});
    await store.write(LocalStore.categoriesBox, 'mia', {'id': 'mia'});
    await store.write(LocalStore.accountsBox, 'bcp', {'id': 'bcp'});
    final settings = MemorySettings(const WalletSettings(onboardingDone: true, currency: 'USD', ownerUid: 'u1'));
    final social = MemorySocial();
    final inbox = CaptureInbox(directory: () async => dir);
    await inbox.add(CaptureEvent(sourceKey: 's', sourceLabel: 's', text: 'Pagaste S/ 5.00', receivedAt: DateTime(2026)));
    final listener = _Listener();
    final c = ProviderContainer(overrides: [
      captureInboxProvider.overrideWithValue(inbox),
      authServiceProvider.overrideWithValue(FakeAuth(current: gabriel)),
      biometricsProvider.overrideWithValue(FakeBiometrics()),
      walletSettingsRepositoryProvider.overrideWithValue(settings),
      hasExistingDataProvider.overrideWithValue(true),
      clearLegacyPinProvider.overrideWithValue(() async {}),
      localStoreProvider.overrideWithValue(store),
      socialRepositoryProvider.overrideWithValue(social),
      paymentListenerProvider.overrideWithValue(listener),
    ]);
    addTearDown(c.dispose);
    c.read(sessionControllerProvider);
    await pumpEventQueue();
    expect(c.read(sessionControllerProvider), isA<Locked>());

    await c.read(sessionControllerProvider.notifier).eraseEverything();

    expect(store.readAll(LocalStore.movementsBox), isEmpty);
    expect(store.readAll(LocalStore.subscriptionsBox), isEmpty);
    final categories = store.readAll(LocalStore.categoriesBox).map((j) => j['id']).toSet();
    expect(categories, isNot(contains('mia')));
    expect(categories, contains('food'), reason: 'vuelven las categorías por defecto');
    expect(settings.value.onboardingDone, isFalse);
    expect(settings.value.currency, 'PEN');
    expect(settings.value.ownerUid, 'u1', reason: 'la wallet sigue siendo de la misma cuenta');
    final account = store.readAll(LocalStore.accountsBox).single;
    expect(account['name'], 'Mi cuenta', reason: 'queda solo la cuenta por defecto');
    expect(account['currency'], 'PEN', reason: 'la moneda por defecto de la wallet, no la anterior');
    expect(account['initialMinor'], 0);
    expect(account['isDefault'], isTrue);
    expect(social.forgetCalls, 1);
    expect(File('${dir.path}/capture_inbox.jsonl').existsSync(), isFalse, reason: 'tampoco quedan textos por procesar');
    expect(listener.cleared, 1, reason: 'en Android se olvidan las apps vistas y elegidas');
    final s = c.read(sessionControllerProvider);
    expect(s, isA<NeedsOnboarding>());
    expect((s as NeedsOnboarding).short, isFalse);
  });

  test('una pasada de captura a medias durante el borrado no escribe en la wallet nueva', () async {
    final settings = _SlowSettings(const WalletSettings(onboardingDone: true, ownerUid: 'u1'));
    final movements = _SlowMovements(HiveMovementRepository(store));
    final inbox = CaptureInbox(directory: () async => dir);
    await inbox.add(CaptureEvent(sourceKey: 's', sourceLabel: 's', text: 'Pagaste S/ 5.00 en Tambo', receivedAt: DateTime(2026)));
    final c = ProviderContainer(overrides: [
      captureInboxProvider.overrideWithValue(inbox),
      authServiceProvider.overrideWithValue(FakeAuth(current: gabriel)),
      biometricsProvider.overrideWithValue(FakeBiometrics()),
      walletSettingsRepositoryProvider.overrideWithValue(settings),
      movementRepositoryProvider.overrideWithValue(movements),
      hasExistingDataProvider.overrideWithValue(true),
      clearLegacyPinProvider.overrideWithValue(() async {}),
      localStoreProvider.overrideWithValue(store),
      socialRepositoryProvider.overrideWithValue(MemorySocial()),
      paymentListenerProvider.overrideWithValue(_Listener()),
    ]);
    addTearDown(c.dispose);
    final session = c.read(sessionControllerProvider.notifier);
    await pumpEventQueue();
    expect(await session.unlockWithFaceId(), isTrue);
    expect(c.read(sessionControllerProvider), isA<Ready>());

    // La pasada se queda leyendo los movimientos.
    final pass = c.read(captureRunnerProvider).run();
    await _until(() => movements.waiting);

    // El borrado se queda guardando los ajustes nuevos, con la sesión aún en Ready.
    final erase = session.eraseEverything();
    await _until(() => settings.waiting);

    // La pasada termina en mitad del borrado.
    movements.release();
    await pass;
    settings.release();
    await erase;

    expect(store.readAll(LocalStore.movementsBox), isEmpty, reason: 'la wallet nueva no recibe nada viejo');
    expect(c.read(sessionControllerProvider), isA<NeedsOnboarding>());
  });

  test('si el canal de Android falla, el borrado termina igual', () async {
    final c = ProviderContainer(overrides: [
      captureInboxProvider.overrideWithValue(CaptureInbox(directory: () async => dir)),
      authServiceProvider.overrideWithValue(FakeAuth(current: gabriel)),
      biometricsProvider.overrideWithValue(FakeBiometrics()),
      walletSettingsRepositoryProvider.overrideWithValue(MemorySettings(const WalletSettings(onboardingDone: true, ownerUid: 'u1'))),
      hasExistingDataProvider.overrideWithValue(true),
      clearLegacyPinProvider.overrideWithValue(() async {}),
      localStoreProvider.overrideWithValue(store),
      socialRepositoryProvider.overrideWithValue(MemorySocial()),
      paymentListenerProvider.overrideWithValue(_Listener(fail: true)),
    ]);
    addTearDown(c.dispose);
    c.read(sessionControllerProvider);
    await pumpEventQueue();
    await c.read(sessionControllerProvider.notifier).eraseEverything();
    expect(c.read(sessionControllerProvider), isA<NeedsOnboarding>());
  });
}

/// Espera (con E/S real de por medio) hasta que se cumpla [done].
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue);
}

/// Registra que se pidió olvidar las preferencias de captura de Android.
class _Listener implements PaymentListener {
  _Listener({this.fail = false});
  final bool fail;
  int cleared = 0;

  @override
  Future<bool> isEnabled() async => false;
  @override
  Future<void> openSettings() async {}
  @override
  Future<List<CaptureApp>> seenApps() async => const [];
  @override
  Future<Set<String>> enabledApps() async => const {};
  @override
  Future<void> setEnabled(String package, bool enabled) async {}
  @override
  Future<void> clearCaptureSettings() async {
    cleared++;
    if (fail) throw StateError('canal');
  }
}

/// Ajustes cuyo primer guardado espera a [release].
class _SlowSettings extends MemorySettings {
  _SlowSettings(super.value);
  final _gate = Completer<void>();
  bool waiting = false;
  bool _done = false;
  void release() => _gate.complete();

  @override
  Future<void> save(WalletSettings s) async {
    if (!_done) {
      _done = true;
      waiting = true;
      await _gate.future;
    }
    await super.save(s);
  }
}

/// Movimientos cuya primera lectura espera a [release].
class _SlowMovements implements MovementRepository {
  _SlowMovements(this._inner);
  final MovementRepository _inner;
  final _gate = Completer<void>();
  bool waiting = false;
  bool _done = false;
  void release() => _gate.complete();

  @override
  Stream<List<Movement>> watchAll() async* {
    if (!_done) {
      _done = true;
      final before = await _inner.watchAll().first;
      waiting = true;
      await _gate.future;
      yield before;
      return;
    }
    yield* _inner.watchAll();
  }

  @override
  Future<void> save(Movement m) => _inner.save(m);
  @override
  Future<void> saveAll(Iterable<Movement> ms) => _inner.saveAll(ms);
  @override
  Future<void> delete(String id) => _inner.delete(id);
  @override
  Future<void> deleteAll(Iterable<String> ids) => _inner.deleteAll(ids);
}
