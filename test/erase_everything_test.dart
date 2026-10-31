import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/storage/local_store.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/friends/presentation/friends_providers.dart';
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
    final settings = MemorySettings(const WalletSettings(onboardingDone: true, currency: 'USD', ownerUid: 'u1'));
    final social = MemorySocial();
    final c = ProviderContainer(overrides: [
      authServiceProvider.overrideWithValue(FakeAuth(current: gabriel)),
      biometricsProvider.overrideWithValue(FakeBiometrics()),
      walletSettingsRepositoryProvider.overrideWithValue(settings),
      hasExistingDataProvider.overrideWithValue(true),
      clearLegacyPinProvider.overrideWithValue(() async {}),
      localStoreProvider.overrideWithValue(store),
      socialRepositoryProvider.overrideWithValue(social),
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
    expect(social.forgetCalls, 1);
    final s = c.read(sessionControllerProvider);
    expect(s, isA<NeedsOnboarding>());
    expect((s as NeedsOnboarding).short, isFalse);
  });
}
