import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/core/storage/local_store.dart';
import 'package:outflow/core/storage/sync_scope.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/capture/data/capture_inbox.dart';
import 'package:outflow/features/cloud/data/cloud_wallet_store.dart';
import 'package:outflow/features/cloud/domain/migration_plan.dart';
import 'package:outflow/features/cloud/presentation/cloud_sync.dart';
import 'package:outflow/features/friends/presentation/friends_providers.dart';
import 'package:outflow/features/wallet/data/hive_movement_repository.dart';
import 'package:outflow/features/wallet/data/wallet_settings_repository.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';
import 'package:outflow/features/wallet/domain/account_balances.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/month_summary.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';

import 'session_controller_test.dart' show FakeAuth, FakeBiometrics, gabriel;
import 'support/fakes.dart';

/// Llavero en memoria.
class _Secure implements FlutterSecureStorage {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      values[key];

  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      values.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Envuelve el almacén de Firestore (falso) y cuenta lo que la app sube.
class _Spy implements CloudWalletStore {
  _Spy(this.inner);
  final CloudWalletStore inner;

  final puts = <String>[];
  final deletes = <String>[];
  final uploads = <WalletDocs>[];
  int wipes = 0;

  /// Toda llamada falla con esto (p. ej. reglas sin publicar).
  CloudUnavailable? failWith;

  /// `uploadAll` espera a que se complete (para editar mientras sube).
  Completer<void>? uploadGate;
  bool uploadStarted = false;

  /// `uploadAll` no termina nunca (sin red).
  bool hangUpload = false;

  /// `put`/`delete` no terminan ni llegan (sin red y la app se cierra).
  bool hangWrites = false;

  /// `resetAt` espera a que se complete.
  Completer<void>? resetGate;

  /// `resetAt` falla como sin red.
  bool resetOffline = false;

  /// `uploadAll` llega al servidor pero la confirmación se pierde (no termina).
  bool hangAfterUpload = false;

  /// Con [manual], `watch` devuelve estos controladores en vez de Firestore.
  bool manual = false;
  final watchers = <String, StreamController<CloudSnapshot>>{};

  Future<T> _guard<T>(Future<T> Function() f) async {
    final e = failWith;
    if (e != null) throw e;
    return f();
  }

  @override
  Future<void> put(String box, String id, Map<String, Object?> json) => _guard(() {
        if (hangWrites) return Completer<void>().future;
        puts.add('$box/$id');
        return inner.put(box, id, json);
      });

  @override
  Future<void> delete(String box, String id) => _guard(() {
        if (hangWrites) return Completer<void>().future;
        deletes.add('$box/$id');
        return inner.delete(box, id);
      });

  @override
  Future<DateTime?> lastChangeAt() => _guard(inner.lastChangeAt);

  @override
  Future<WalletDocs> readAll() => _guard(inner.readAll);

  @override
  Future<void> uploadAll(WalletDocs docs) => _guard(() async {
        uploadStarted = true;
        if (hangUpload) await Completer<void>().future;
        await uploadGate?.future;
        uploads.add(docs);
        await inner.uploadAll(docs);
        if (hangAfterUpload) await Completer<void>().future;
      });

  @override
  Future<Map<String, Set<String>>> idsWrittenBy(String writer) => _guard(() => inner.idsWrittenBy(writer));

  @override
  Stream<CloudSnapshot> watch(String box) {
    final e = failWith;
    if (e != null) return Stream.error(e);
    if (manual) return (watchers[box] ??= StreamController<CloudSnapshot>.broadcast()).stream;
    return inner.watch(box);
  }

  @override
  Future<DateTime?> resetAt() => _guard(() async {
        if (resetOffline) throw const CloudUnavailable(permissionDenied: false);
        await resetGate?.future;
        return inner.resetAt();
      });

  @override
  Future<void> wipe(DateTime at) => _guard(() {
        wipes++;
        return inner.wipe(at);
      });
}

Map<String, Map<String, Object?>> _box(LocalStore s, String box) => s.readById(box);

Future<void> _until(bool Function() cond, {String? reason}) async {
  for (var i = 0; i < 400; i++) {
    if (cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('No se cumplió a tiempo: ${reason ?? ''}');
}

final _nov = DateTime(2026, 11, 3, 10);

Movement _mov(String id, int minor, {MovementKind kind = MovementKind.expense, String? accountId, String category = 'food'}) =>
    Movement(
      id: id,
      kind: kind,
      amount: Money(minor, 'PEN'),
      categoryId: category,
      date: _nov,
      createdAt: _nov,
      title: 'Prueba $id',
      accountId: accountId,
    );

void main() {
  late Directory dir;
  late Directory docs;
  late LocalStore store;
  late FakeFirebaseFirestore db;
  late _Secure secure;
  final spies = <String, _Spy>{};

  _Spy spyFor(String uid) => spies[uid] ??= _Spy(FirestoreCloudWalletStore(db, uid, writer: store.installToken));

  /// Otro dispositivo de la misma cuenta.
  CloudWalletStore cloudOf(String uid) => FirestoreCloudWalletStore(db, uid, writer: () => 'otro-dispositivo');

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('outflow_cloud');
    docs = Directory('${dir.path}/docs')..createSync();
    Hive.init(dir.path);
    store = await LocalStore.openUnencrypted();
    db = FakeFirebaseFirestore();
    secure = _Secure();
    spies.clear();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    dir.deleteSync(recursive: true);
  });

  List<Override> base({Duration timeout = const Duration(seconds: 2)}) => [
        localStoreProvider.overrideWithValue(store),
        secureStorageProvider.overrideWithValue(secure),
        cloudBackupDirProvider.overrideWithValue(() async => docs),
        cloudTimeoutProvider.overrideWithValue(timeout),
        cloudWalletStoreProvider.overrideWith((ref) {
          final uid = ref.watch(currentAccountProvider.select((a) => a?.uid));
          return uid == null ? null : spyFor(uid);
        }),
      ];

  /// Una apertura de la app con [account] (sin la sesión real).
  ProviderContainer open(Account? account, {Duration timeout = const Duration(seconds: 2)}) {
    final c = ProviderContainer(overrides: [
      ...base(timeout: timeout),
      currentAccountProvider.overrideWithValue(account),
      walletDownloadedProvider.overrideWithValue(() {}),
    ]);
    addTearDown(c.dispose);
    c.listen(cloudSyncProvider, (_, _) {});
    return c;
  }

  CloudSyncState stateOf(ProviderContainer c) => c.read(cloudSyncStateProvider);

  Future<void> owner(String uid, {bool faceId = false}) => store.write(
        LocalStore.settingsBox,
        'wallet.settings',
        WalletSettings(ownerUid: uid, faceIdEnabled: faceId, onboardingDone: true).toJson(),
      );

  /// Lo que sube la app al sincronizar por primera vez una wallet con [m1].
  Future<ProviderContainer> migrated(String uid) async {
    await owner(uid);
    await store.write(LocalStore.movementsBox, 'm1', _mov('m1', 1000).toJson());
    final c = open(Account(uid: uid, email: 'x@example.com', displayName: 'X'));
    await _until(() => stateOf(c) == CloudSyncState.live, reason: 'live');
    return c;
  }

  test('Review Focus 1: un cambio remoto aplicado no genera ningún put', () async {
    await migrated('u1');
    final spy = spyFor('u1');
    spy.puts.clear();
    spy.deletes.clear();
    await store.write(LocalStore.settingsBox, 'wallet.settings',
        const WalletSettings(ownerUid: 'u1', faceIdEnabled: true, onboardingDone: true).toJson());
    await _until(() => spy.puts.isNotEmpty);
    spy.puts.clear();

    // Otro dispositivo de la misma cuenta escribe en la nube.
    await cloudOf('u1').put(LocalStore.movementsBox, 'r1', _mov('r1', 300).toJson());
    await cloudOf('u1').put(LocalStore.settingsBox, 'wallet.settings', {'currency': 'USD', 'onboardingDone': true});
    await cloudOf('u1').delete(LocalStore.movementsBox, 'm1');

    await _until(() => _box(store, LocalStore.movementsBox).keys.toSet().containsAll(['r1']) &&
        !_box(store, LocalStore.movementsBox).containsKey('m1'));
    await _until(() => store.read(LocalStore.settingsBox, 'wallet.settings')?['currency'] == 'USD');
    await pumpEventQueue();
    expect(spy.puts, isEmpty, reason: 'lo que llega de la nube no se devuelve');
    expect(spy.deletes, isEmpty);
    final settings = store.read(LocalStore.settingsBox, 'wallet.settings')!;
    expect(settings['faceIdEnabled'], isTrue, reason: 'Face ID es del dispositivo');
    expect(settings['ownerUid'], 'u1');
  });

  test('Review Focus 2: nube llena y local vacío → Hive igual a la nube, mismo resumen y saldos', () async {
    final accounts = [
      newDefaultAccount('PEN').copyWith(initialMinor: 1000),
      WalletAccount(id: 'bcp', name: 'BCP', type: AccountType.bank, currency: 'PEN', initialMinor: 50000, initialDate: DateTime(2026, 10)),
    ];
    final movements = [
      _mov('m1', 2500),
      _mov('m2', 100000, kind: MovementKind.income, accountId: 'bcp', category: 'salary'),
      _mov('m3', 1200, accountId: 'bcp'),
    ];
    final settings = WalletSettings(onboardingDone: true, walletStartedAt: DateTime(2026, 10), currency: 'PEN');
    final cloudDocs = <String, Map<String, Map<String, Object?>>>{
      LocalStore.accountsBox: {for (final a in accounts) a.id: a.toJson()},
      LocalStore.movementsBox: {for (final m in movements) m.id: m.toJson()},
      LocalStore.categoriesBox: {for (final c in defaultCategories()) c.id: c.toJson()},
      LocalStore.settingsBox: {'wallet.settings': toCloud(LocalStore.settingsBox, 'wallet.settings', settings.toJson())},
    };
    await cloudOf('u1').uploadAll(cloudDocs);
    // Reinstalación: solo lo que crea la app al abrir.
    await owner('u1', faceId: true);
    await store.write(LocalStore.accountsBox, kDefaultAccountId, newDefaultAccount('PEN').toJson());

    final c = open(gabriel);
    await _until(() => stateOf(c) == CloudSyncState.live);

    for (final box in [LocalStore.accountsBox, LocalStore.movementsBox, LocalStore.categoriesBox]) {
      expect(_box(store, box), cloudDocs[box], reason: box);
    }
    final local = WalletSettings.fromJson(store.read(LocalStore.settingsBox, 'wallet.settings')!);
    expect(local.faceIdEnabled, isTrue, reason: 'lo del dispositivo se conserva');
    expect(local.ownerUid, 'u1');

    final localMovements = store.readAll(LocalStore.movementsBox).map(Movement.fromJson).toList();
    final localAccounts = store.readAll(LocalStore.accountsBox).map(WalletAccount.fromJson).toList();
    MonthSummary summary(List<Movement> m, WalletSettings s) =>
        MonthSummary.compute(movements: m, subscriptions: const [], settings: s, month: DateTime(2026, 11), now: _nov);
    final a = summary(movements, settings);
    final b = summary(localMovements, local);
    expect([b.income.minor, b.expense.minor, b.remaining.minor, b.carriedIn.minor],
        [a.income.minor, a.expense.minor, a.remaining.minor, a.carriedIn.minor]);
    expect(computeBalances(localAccounts, localMovements), computeBalances(accounts, movements));
    expect(spyFor('u1').uploads, isEmpty, reason: 'descargar no sube nada');
    expect(spyFor('u1').puts, isEmpty, reason: 'la "Mi cuenta" vacía local no pisa la de la nube');
    expect(secure.values['outflow.cloud.migrated.u1'], isNotNull);
    expect(secure.values['outflow.cloud.loadedAt.u1'], isNotNull);
  });

  test('Review Focus 3: permiso denegado → unavailable, sin marca y los datos intactos; reintentar sube', () async {
    await owner('u1');
    await store.write(LocalStore.movementsBox, 'm1', _mov('m1', 1000).toJson());
    final before = _box(store, LocalStore.movementsBox);
    spyFor('u1').failWith = const CloudUnavailable(permissionDenied: true);
    final c = open(gabriel);
    await _until(() => stateOf(c) == CloudSyncState.unavailable);
    await store.write(LocalStore.movementsBox, 'm2', _mov('m2', 50).toJson());
    await pumpEventQueue();
    expect(secure.values.keys.where((k) => k.startsWith('outflow.cloud.migrated')), isEmpty);
    expect(_box(store, LocalStore.movementsBox)['m1'], before['m1']);
    expect(_box(store, LocalStore.movementsBox).containsKey('m2'), isTrue);

    spyFor('u1').failWith = null;
    await c.read(cloudSyncProvider.notifier).retry();
    await _until(() => stateOf(c) == CloudSyncState.live);
    final cloud = await cloudOf('u1').readAll();
    expect(cloud[LocalStore.movementsBox]!.keys.toSet(), {'m1', 'm2'});
    expect(secure.values['outflow.cloud.migrated.u1'], isNotNull);
  });

  test('permiso denegado en el espejo en vivo → unavailable y el cambio se reenvía al reintentar', () async {
    final c = await migrated('u1');
    spyFor('u1').failWith = const CloudUnavailable(permissionDenied: true);
    await store.write(LocalStore.movementsBox, 'm9', _mov('m9', 9).toJson());
    await _until(() => stateOf(c) == CloudSyncState.unavailable);
    spyFor('u1').failWith = null;
    await c.read(cloudSyncProvider.notifier).retry();
    await _until(() => stateOf(c) == CloudSyncState.live);
    await _until(() => spyFor('u1').puts.contains('movements/m9'));
    expect((await cloudOf('u1').readAll())[LocalStore.movementsBox]!.containsKey('m9'), isTrue);
    expect(_box(store, LocalStore.movementsBox).containsKey('m9'), isTrue);
  });

  group('cambios sin confirmar tras reabrir la app', () {
    test('un cambio rechazado (reglas sin publicar) llega a la nube al reabrir y no se revierte', () async {
      final c = await migrated('u1');
      spyFor('u1').failWith = const CloudUnavailable(permissionDenied: true);
      await store.write(LocalStore.movementsBox, 'm1', _mov('m1', 1111).toJson());
      await _until(() => stateOf(c) == CloudSyncState.unavailable);
      c.dispose();
      spyFor('u1').failWith = null;

      final again = open(gabriel);
      await _until(() => stateOf(again) == CloudSyncState.live);
      await _until(() => !store.isDirty(LocalStore.movementsBox, 'm1'));
      await pumpEventQueue();
      expect((await cloudOf('u1').readAll())[LocalStore.movementsBox]!['m1']!['amount'], {'minor': 1111, 'currency': 'PEN'});
      expect(_box(store, LocalStore.movementsBox)['m1']!['amount'], {'minor': 1111, 'currency': 'PEN'});
    });

    test('mientras el servidor no confirma, lo de la nube no pisa el cambio local al reabrir', () async {
      final c = await migrated('u1');
      spyFor('u1').hangWrites = true;
      await store.write(LocalStore.movementsBox, 'm1', _mov('m1', 2222).toJson());
      await pumpEventQueue();
      c.dispose();

      // Sigue sin red para las escrituras: la escucha trae la versión vieja.
      final again = open(gabriel);
      await _until(() => stateOf(again) == CloudSyncState.live);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(_box(store, LocalStore.movementsBox)['m1']!['amount'], {'minor': 2222, 'currency': 'PEN'});
      expect(store.isDirty(LocalStore.movementsBox, 'm1'), isTrue);
    });

    test('un borrado sin enviar no resucita al reabrir y se borra en la nube', () async {
      final c = await migrated('u1');
      spyFor('u1').hangWrites = true;
      await HiveMovementRepository(store).delete('m1');
      await pumpEventQueue();
      c.dispose();
      spyFor('u1').hangWrites = false;

      final again = open(gabriel);
      await _until(() => stateOf(again) == CloudSyncState.live);
      await _until(() => spyFor('u1').deletes.contains('movements/m1'));
      await pumpEventQueue();
      expect(_box(store, LocalStore.movementsBox).containsKey('m1'), isFalse);
      expect((await cloudOf('u1').readAll())[LocalStore.movementsBox] ?? {}, isEmpty);
    });

    test('un documento nuevo sin enviar se sube al reabrir', () async {
      final c = await migrated('u1');
      spyFor('u1').hangWrites = true;
      await store.write(LocalStore.movementsBox, 'm-new', _mov('m-new', 3).toJson());
      await pumpEventQueue();
      c.dispose();
      spyFor('u1').hangWrites = false;

      final again = open(gabriel);
      await _until(() => stateOf(again) == CloudSyncState.live);
      await _until(() => spyFor('u1').puts.contains('movements/m-new'));
      await pumpEventQueue();
      expect((await cloudOf('u1').readAll())[LocalStore.movementsBox]!.containsKey('m-new'), isTrue);
      expect(_box(store, LocalStore.movementsBox).containsKey('m-new'), isTrue);
    });

    test('lo escrito antes de comprobar resetAt no sube si otro teléfono borró todo', () async {
      final b = await migrated('u1');
      b.dispose();
      // El teléfono A borra todo mientras B está sin red.
      await cloudOf('u1').wipe(DateTime.now().add(const Duration(hours: 1)));
      await cloudOf('u1').put(LocalStore.movementsBox, 'm-a', _mov('m-a', 1).toJson());
      final spy = spyFor('u1')
        ..puts.clear()
        ..deletes.clear()
        ..resetGate = Completer<void>();

      final again = open(gabriel);
      // La sincronización de cobros escribe antes de que llegue resetAt.
      await store.write(LocalStore.movementsBox, 'sub:s1:2026-11-01', _mov('sub:s1:2026-11-01', 999).toJson());
      await pumpEventQueue();
      expect(spy.puts, isEmpty, reason: 'nada se envía antes de comprobar resetAt');
      spy.resetGate!.complete();
      await _until(() => stateOf(again) == CloudSyncState.live);
      await pumpEventQueue();
      expect(spy.puts, isEmpty);
      expect(spy.deletes, isEmpty);
      final cloud = await cloudOf('u1').readAll();
      expect(cloud[LocalStore.movementsBox]!.keys.toSet(), {'m-a'});
      for (final box in kSyncedBoxes) {
        expect(_box(store, box), cloud[box] ?? {}, reason: box);
      }
      expect(store.dirtyKeys(), isEmpty);
    });
  });

  group('borrado pendiente de otra apertura', () {
    String token() => store.read(LocalStore.settingsBox, LocalStore.installKey)!['token'] as String;

    test('si otro dispositivo escribió después, no se borra la nube y se descarga', () async {
      final c = await migrated('u1');
      c.dispose();
      secure.values['outflow.cloud.pendingWipe.u1'] =
          jsonEncode({'token': token(), 'at': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String()});
      await cloudOf('u1').put(LocalStore.movementsBox, 'm-other', _mov('m-other', 2).toJson());

      final again = open(gabriel);
      await _until(() => stateOf(again) == CloudSyncState.live);
      expect(spyFor('u1').wipes, 0);
      expect(secure.values['outflow.cloud.pendingWipe.u1'], isNull);
      final cloud = await cloudOf('u1').readAll();
      expect(cloud[LocalStore.movementsBox]!.keys.toSet(), {'m1', 'm-other'});
      expect(_box(store, LocalStore.movementsBox).keys.toSet(), {'m1', 'm-other'});
    });

    test('las escrituras propias encoladas antes del borrado no lo deshacen al reconectar', () async {
      final c = await migrated('u1');
      c.dispose();
      // Este teléfono borró todo sin red: lo local ya es la wallet nueva.
      await store.applyRemoteAll(LocalStore.movementsBox, {'m1': null, 'm-fresh': _mov('m-fresh', 5).toJson()});
      secure.values['outflow.cloud.pendingWipe.u1'] =
          jsonEncode({'token': token(), 'at': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String()});
      // Al volver la red llegan sus propias escrituras de antes del borrado.
      await spyFor('u1').inner.put(LocalStore.movementsBox, 'm-offline', _mov('m-offline', 9).toJson());

      final again = open(gabriel);
      await _until(() => stateOf(again) == CloudSyncState.live && spyFor('u1').wipes == 1);
      final cloud = await cloudOf('u1').readAll();
      expect(cloud[LocalStore.movementsBox]!.keys.toSet(), {'m-fresh'}, reason: 'la nube vacía más lo de después del borrado');
      expect(_box(store, LocalStore.movementsBox).keys.toSet(), {'m-fresh'});
      expect(secure.values['outflow.cloud.pendingWipe.u1'], isNull);
    });

    test('sin nada más nuevo, termina el borrado', () async {
      final c = await migrated('u1');
      c.dispose();
      secure.values['outflow.cloud.pendingWipe.u1'] =
          jsonEncode({'token': token(), 'at': DateTime.now().add(const Duration(minutes: 5)).toIso8601String()});
      final again = open(gabriel);
      await _until(() => stateOf(again) == CloudSyncState.live && spyFor('u1').wipes == 1);
      expect(secure.values['outflow.cloud.pendingWipe.u1'], isNull);
    });

    test('la marca de otra instalación se ignora', () async {
      final c = await migrated('u1');
      c.dispose();
      secure.values['outflow.cloud.pendingWipe.u1'] =
          jsonEncode({'token': 'otra-instalacion', 'at': DateTime.now().add(const Duration(minutes: 5)).toIso8601String()});
      final again = open(gabriel);
      await _until(() => stateOf(again) == CloudSyncState.live);
      expect(spyFor('u1').wipes, 0);
      expect(secure.values['outflow.cloud.pendingWipe.u1'], isNull);
      expect((await cloudOf('u1').readAll())[LocalStore.movementsBox]!.keys.toSet(), {'m1'});
    });
  });

  test('el pendiente queda anotado antes de escribir el dato', () async {
    await migrated('u1');
    final sync = store.beforeChange!;
    final seen = <String>[];
    store.beforeChange = (box, ids, {required deleted}) async {
      await sync(box, ids, deleted: deleted);
      for (final id in ids) {
        // En este punto el dato aún no está escrito, pero el pendiente sí.
        seen.add('$id dato:${store.read(box, id) != null} pendiente:${store.isDirty(box, id)}');
      }
    };
    await store.write(LocalStore.movementsBox, 'm-a', _mov('m-a', 1).toJson());
    await store.writeAll(LocalStore.movementsBox, {'m-b': _mov('m-b', 2).toJson()});
    await store.remove(LocalStore.movementsBox, 'm1');
    await store.write(LocalStore.settingsBox, 'account.preview', const {'signedIn': true});
    expect(seen, [
      'm-a dato:false pendiente:true',
      'm-b dato:false pendiente:true',
      'm1 dato:true pendiente:true',
      'account.preview dato:false pendiente:false',
    ]);
  });

  test('Review Focus 4: lo local de otra cuenta no se sube, queda la copia y vuelve a su dueño', () async {
    final theirs = _mov('m-u0', 4200).toJson();
    await owner('u0');
    await store.write(LocalStore.movementsBox, 'm-u0', theirs);
    await cloudOf('u1').uploadAll({
      LocalStore.movementsBox: {'m-u1': _mov('m-u1', 100).toJson()},
      LocalStore.accountsBox: {kDefaultAccountId: newDefaultAccount('PEN').toJson()},
    });

    final c1 = open(gabriel);
    await _until(() => stateOf(c1) == CloudSyncState.live);
    final u1Cloud = await cloudOf('u1').readAll();
    expect(u1Cloud[LocalStore.movementsBox]!.keys.toSet(), {'m-u1'}, reason: 'nada de u0 sube a u1');
    expect((await cloudOf('u0').readAll()).values.every((b) => b.isEmpty), isTrue);
    expect(_box(store, LocalStore.movementsBox).keys.toSet(), {'m-u1'}, reason: 'lo de u0 ya no se muestra');
    expect(store.read(LocalStore.settingsBox, 'wallet.settings')!['ownerUid'], 'u1');
    final backup = File('${docs.path}/backup_u0.json');
    expect(backup.existsSync(), isTrue);
    final saved = jsonDecode(backup.readAsStringSync()) as Map;
    expect((saved['docs'] as Map)[LocalStore.movementsBox], {'m-u0': theirs});
    c1.dispose();

    // Vuelve su dueño; su nube está vacía.
    final c0 = open(const Account(uid: 'u0', email: 'o@example.com', displayName: 'Otro'));
    await _until(() => stateOf(c0) == CloudSyncState.live);
    expect(_box(store, LocalStore.movementsBox), {'m-u0': theirs});
    expect(store.read(LocalStore.settingsBox, 'wallet.settings')!['ownerUid'], 'u0');
    final u0Cloud = await cloudOf('u0').readAll();
    expect(u0Cloud[LocalStore.movementsBox], {'m-u0': theirs});
    expect((await cloudOf('u1').readAll())[LocalStore.movementsBox]!.keys.toSet(), {'m-u1'});
    expect(backup.existsSync(), isFalse, reason: 'la copia ya está en su nube');
    expect(File('${docs.path}/backup_u1.json').existsSync(), isFalse, reason: 'lo de u1 ya estaba en su nube');
  });

  test('Review Focus 4b: la copia de otra cuenta con su nube llena se trata como preguntar', () async {
    await owner('u0');
    await store.write(LocalStore.movementsBox, 'm-u0', _mov('m-u0', 4200).toJson());
    final c1 = open(gabriel);
    await _until(() => stateOf(c1) == CloudSyncState.live);
    c1.dispose();
    await cloudOf('u0').put(LocalStore.movementsBox, 'm-cloud', _mov('m-cloud', 1).toJson());

    final c0 = open(const Account(uid: 'u0', email: 'o@example.com', displayName: 'Otro'));
    await _until(() => stateOf(c0) == CloudSyncState.needsChoice);
    expect(_box(store, LocalStore.movementsBox).keys.toSet(), {'m-u0'});
    await c0.read(cloudSyncProvider.notifier).chooseMerge();
    await _until(() => stateOf(c0) == CloudSyncState.live);
    expect((await cloudOf('u0').readAll())[LocalStore.movementsBox]!.keys.toSet(), {'m-u0', 'm-cloud'});
    expect(File('${docs.path}/backup_u0.json').existsSync(), isFalse);
  });

  test('una copia anterior a un "Borrar toda la información" de su dueño no se restaura', () async {
    await owner('u0');
    await store.write(LocalStore.movementsBox, 'm-u0', _mov('m-u0', 4200).toJson());
    final c1 = open(gabriel);
    await _until(() => stateOf(c1) == CloudSyncState.live);
    c1.dispose();
    expect(File('${docs.path}/backup_u0.json').existsSync(), isTrue);
    // Su dueño borró todo desde otro teléfono.
    await cloudOf('u0').wipe(DateTime.now().add(const Duration(minutes: 1)));

    final c0 = open(const Account(uid: 'u0', email: 'o@example.com', displayName: 'Otro'));
    await _until(() => stateOf(c0) == CloudSyncState.live);
    expect(_box(store, LocalStore.movementsBox), isEmpty);
    expect((await cloudOf('u0').readAll())[LocalStore.movementsBox] ?? {}, isEmpty);
    expect(File('${docs.path}/backup_u0.json').existsSync(), isFalse);
  });

  test('Review Focus 5: un resetAt más nuevo vacía la caché local sin subir nada', () async {
    final first = await migrated('u1');
    first.dispose();
    // Otro teléfono borró todo y empezó de nuevo.
    final at = DateTime.now().add(const Duration(hours: 1));
    await cloudOf('u1').wipe(at);
    await cloudOf('u1').put(LocalStore.movementsBox, 'm-new', _mov('m-new', 5).toJson());
    final spy = spyFor('u1');
    spy.puts.clear();
    spy.deletes.clear();
    spy.uploads.clear();

    final c = open(gabriel);
    await _until(() => stateOf(c) == CloudSyncState.live);
    expect(_box(store, LocalStore.movementsBox).keys.toSet(), {'m-new'});
    expect(store.read(LocalStore.settingsBox, 'wallet.settings')!['ownerUid'], 'u1');
    expect(spy.puts, isEmpty);
    expect(spy.deletes, isEmpty);
    expect(spy.uploads, isEmpty);
    expect(DateTime.parse(secure.values['outflow.cloud.loadedAt.u1']!).isBefore(at), isFalse);

    // Lo nuevo sube, y al volver a abrir no se vuelve a vaciar.
    await store.write(LocalStore.movementsBox, 'm-local', _mov('m-local', 7).toJson());
    await _until(() => spy.puts.contains('movements/m-local'));
    c.dispose();
    final again = open(gabriel);
    await _until(() => stateOf(again) == CloudSyncState.live);
    await pumpEventQueue();
    expect(_box(store, LocalStore.movementsBox).keys.toSet(), {'m-new', 'm-local'});
  });

  test('al volver a primer plano se comprueba resetAt', () async {
    final c = await migrated('u1');
    final spy = spyFor('u1');
    spy.puts.clear();
    await cloudOf('u1').wipe(DateTime.now().add(const Duration(hours: 1)));
    await c.read(cloudSyncProvider.notifier).onResume();
    await _until(() => _box(store, LocalStore.movementsBox).isEmpty);
    expect(stateOf(c), CloudSyncState.live);
    expect(spy.puts, isEmpty);
  });

  test('un alta, un cambio y un borrado locales llegan a la nube', () async {
    await migrated('u1');
    final repo = HiveMovementRepository(store);
    Future<Map<String, Map<String, Object?>>> cloudMovements() async =>
        (await cloudOf('u1').readAll())[LocalStore.movementsBox] ?? {};

    await repo.save(_mov('m2', 200));
    await _until(() => spyFor('u1').puts.contains('movements/m2'));
    expect((await cloudMovements())['m2'], _mov('m2', 200).toJson());

    await repo.save(_mov('m2', 250));
    await _until(() => spyFor('u1').puts.where((p) => p == 'movements/m2').length == 2);
    expect((await cloudMovements())['m2'], _mov('m2', 250).toJson());

    await repo.delete('m2');
    await _until(() => spyFor('u1').deletes.contains('movements/m2'));
    expect((await cloudMovements()).containsKey('m2'), isFalse);

    // Lo que es solo del dispositivo no sube.
    await store.write(LocalStore.settingsBox, 'account.preview', const {'signedIn': true});
    await store.write(LocalStore.settingsBox, 'wallet.settings',
        const WalletSettings(ownerUid: 'u1', faceIdEnabled: true, currency: 'USD').toJson());
    await _until(() => spyFor('u1').puts.contains('settings/wallet.settings'));
    expect(spyFor('u1').puts.where((p) => p.contains('account.preview')), isEmpty);
    final w = (await cloudOf('u1').readAll())[LocalStore.settingsBox]!['wallet.settings']!;
    expect(w['currency'], 'USD');
    expect(w.containsKey('faceIdEnabled'), isFalse);
    expect(w.containsKey('ownerUid'), isFalse);
  });

  test('nube vacía: sube todo, marca tras confirmar, y lo editado mientras sube no se pierde', () async {
    await owner('u1');
    await store.write(LocalStore.movementsBox, 'm1', _mov('m1', 1000).toJson());
    final spy = spyFor('u1')..uploadGate = Completer<void>();
    final c = open(gabriel);
    await _until(() => spy.uploadStarted);
    await store.write(LocalStore.movementsBox, 'm2', _mov('m2', 20).toJson());
    expect(secure.values['outflow.cloud.migrated.u1'], isNull, reason: 'sin confirmación no hay marca');
    expect(spy.puts, isEmpty, reason: 'nada sube antes de terminar la migración');
    spy.uploadGate!.complete();
    await _until(() => stateOf(c) == CloudSyncState.live);
    await _until(() => spy.puts.contains('movements/m2'));
    final cloud = await cloudOf('u1').readAll();
    expect(cloud[LocalStore.movementsBox]!.keys.toSet(), {'m1', 'm2'});
    expect(cloud[LocalStore.settingsBox]!['wallet.settings']!.containsKey('ownerUid'), isFalse);
    expect(secure.values['outflow.cloud.migrated.u1'], isNotNull);
  });

  test('sin respuesta del servidor al subir → unavailable y sin marca', () async {
    await owner('u1');
    await store.write(LocalStore.movementsBox, 'm1', _mov('m1', 1000).toJson());
    spyFor('u1').hangUpload = true;
    final c = open(gabriel, timeout: const Duration(milliseconds: 100));
    await _until(() => stateOf(c) == CloudSyncState.unavailable);
    expect(secure.values['outflow.cloud.migrated.u1'], isNull);
    expect(_box(store, LocalStore.movementsBox).containsKey('m1'), isTrue);
  });

  group('ambos con datos', () {
    Future<ProviderContainer> asking() async {
      await owner('u1');
      await store.write(LocalStore.movementsBox, 'm-local', _mov('m-local', 10).toJson());
      await store.write(LocalStore.accountsBox, kDefaultAccountId, newDefaultAccount('PEN').copyWith(initialMinor: 700).toJson());
      await cloudOf('u1').uploadAll({
        LocalStore.movementsBox: {'m-cloud': _mov('m-cloud', 20).toJson()},
        LocalStore.accountsBox: {kDefaultAccountId: newDefaultAccount('PEN').copyWith(initialMinor: 100).toJson()},
      });
      final c = open(gabriel);
      await _until(() => stateOf(c) == CloudSyncState.needsChoice);
      return c;
    }

    test('pregunta sin subir ni pisar nada; Unir junta lo de ambos sin duplicar', () async {
      final c = await asking();
      // Mientras tanto la app sigue en local.
      await store.write(LocalStore.movementsBox, 'm-edit', _mov('m-edit', 30).toJson());
      await pumpEventQueue();
      final spy = spyFor('u1');
      expect(spy.puts, isEmpty);
      expect(spy.uploads, isEmpty);
      expect(_box(store, LocalStore.movementsBox).keys.toSet(), {'m-local', 'm-edit'});
      expect(secure.values['outflow.cloud.migrated.u1'], isNull);

      await c.read(cloudSyncProvider.notifier).chooseMerge();
      await _until(() => stateOf(c) == CloudSyncState.live);
      final cloud = await cloudOf('u1').readAll();
      expect(cloud[LocalStore.movementsBox]!.keys.toSet(), {'m-cloud', 'm-local', 'm-edit'});
      expect(cloud[LocalStore.accountsBox]!.keys.toSet(), {kDefaultAccountId});
      expect(cloud[LocalStore.accountsBox]![kDefaultAccountId]!['initialMinor'], 100, reason: 'gana la nube');
      for (final box in kSyncedBoxes) {
        expect(_box(store, box), cloud[box] ?? {}, reason: 'los dos teléfonos quedan iguales: $box');
      }
      expect(secure.values['outflow.cloud.migrated.u1'], isNotNull);
    });

    test('Usar solo los de la nube descarta lo local', () async {
      final c = await asking();
      await c.read(cloudSyncProvider.notifier).chooseCloudOnly();
      await _until(() => stateOf(c) == CloudSyncState.live);
      expect(_box(store, LocalStore.movementsBox).keys.toSet(), {'m-cloud'});
      expect(_box(store, LocalStore.accountsBox)[kDefaultAccountId]!['initialMinor'], 100);
      expect(spyFor('u1').uploads, isEmpty);
      expect((await cloudOf('u1').readAll())[LocalStore.movementsBox]!.keys.toSet(), {'m-cloud'});
    });
  });

  test('vista previa o sin Firebase: no hace nada', () async {
    await store.write(LocalStore.movementsBox, 'm1', _mov('m1', 1).toJson());
    final c = ProviderContainer(overrides: [
      localStoreProvider.overrideWithValue(store),
      secureStorageProvider.overrideWithValue(secure),
      currentAccountProvider.overrideWithValue(const Account(uid: 'preview', email: 'p@example.com', displayName: 'P')),
    ]);
    addTearDown(c.dispose);
    c.listen(cloudSyncProvider, (_, _) {});
    await pumpEventQueue();
    expect(c.read(cloudWalletStoreProvider), isNull);
    expect(stateOf(c), CloudSyncState.idle);
    expect(secure.values, isEmpty);
  });

  test('una marca de otra instalación (llavero del iPhone tras reinstalar) no cuenta como migrado', () async {
    await cloudOf('u1').uploadAll({
      LocalStore.accountsBox: {kDefaultAccountId: newDefaultAccount('PEN').copyWith(initialMinor: 1000).toJson()},
      LocalStore.movementsBox: {'m1': _mov('m1', 1).toJson()},
    });
    secure.values['outflow.cloud.migrated.u1'] = 'instalacion-anterior';
    await owner('u1');
    // La app crea "Mi cuenta" vacía al abrir: no debe pisar la de la nube.
    await store.write(LocalStore.accountsBox, kDefaultAccountId, newDefaultAccount('PEN').toJson());
    final c = open(gabriel);
    await _until(() => stateOf(c) == CloudSyncState.live);
    expect((await cloudOf('u1').readAll())[LocalStore.accountsBox]![kDefaultAccountId]!['initialMinor'], 1000);
    expect(_box(store, LocalStore.accountsBox)[kDefaultAccountId]!['initialMinor'], 1000);
    expect(_box(store, LocalStore.movementsBox).keys.toSet(), {'m1'});
    expect(secure.values['outflow.cloud.migrated.u1'], isNot('instalacion-anterior'));
  });

  test('snapshots con escrituras pendientes o de caché: se aplican solo cuando confirma el servidor', () async {
    final spy = spyFor('u1')..manual = true;
    final c = await migrated('u1');
    expect(stateOf(c), CloudSyncState.live);
    final w = spy.watchers[LocalStore.movementsBox]!;
    CloudDoc doc(String id, [int minor = 1]) => CloudDoc(box: LocalStore.movementsBox, id: id, json: _mov(id, minor).toJson());

    w.add(CloudSnapshot(changes: [doc('x')], fromCache: false, hasPendingWrites: true));
    await pumpEventQueue();
    expect(_box(store, LocalStore.movementsBox).containsKey('x'), isFalse, reason: 'con escrituras pendientes no se aplica');

    w.add(const CloudSnapshot(changes: [], fromCache: false, hasPendingWrites: false));
    await _until(() => _box(store, LocalStore.movementsBox).containsKey('x'));

    w.add(const CloudSnapshot(changes: [CloudDoc(box: 'movements', id: 'x', json: null)], fromCache: true, hasPendingWrites: false));
    await pumpEventQueue();
    expect(_box(store, LocalStore.movementsBox).containsKey('x'), isTrue, reason: 'un borrado de caché espera al servidor');

    w.add(const CloudSnapshot(changes: [], fromCache: false, hasPendingWrites: false));
    await _until(() => !_box(store, LocalStore.movementsBox).containsKey('x'));
    expect(_box(store, LocalStore.movementsBox).containsKey('m1'), isTrue);
    expect(spy.puts, isEmpty);
  });

  test('cerrar sesión deja de escuchar y de subir', () async {
    final account = StateNotifierLike(gabriel);
    final c = ProviderContainer(overrides: [
      ...base(),
      currentAccountProvider.overrideWith((ref) => ref.watch(account.provider)),
      walletDownloadedProvider.overrideWithValue(() {}),
    ]);
    addTearDown(c.dispose);
    c.listen(cloudSyncProvider, (_, _) {});
    await owner('u1');
    await _until(() => stateOf(c) == CloudSyncState.live);
    c.read(account.provider.notifier).set(null);
    await pumpEventQueue();
    expect(stateOf(c), CloudSyncState.idle);
    spyFor('u1').puts.clear();
    await store.write(LocalStore.movementsBox, 'after', _mov('after', 1).toJson());
    await pumpEventQueue();
    expect(spyFor('u1').puts, isEmpty);
  });

  group('con la sesión real', () {
    List<Override> session(FakeAuth auth) => [
          ...base(),
          authServiceProvider.overrideWithValue(auth),
          biometricsProvider.overrideWithValue(FakeBiometrics()),
          clearLegacyPinProvider.overrideWithValue(() async {}),
          socialRepositoryProvider.overrideWithValue(MemorySocial()),
          captureInboxProvider.overrideWithValue(CaptureInbox(directory: () async => docs)),
        ];

    test('borrar toda la información vacía la nube sin que el espejo suba los borrados', () async {
      await owner('u1');
      await store.write(LocalStore.movementsBox, 'm1', _mov('m1', 1000).toJson());
      final c = ProviderContainer(overrides: session(FakeAuth(current: gabriel)));
      addTearDown(c.dispose);
      c.listen(cloudSyncProvider, (_, _) {});
      await _until(() => stateOf(c) == CloudSyncState.live);
      final spy = spyFor('u1');
      spy.deletes.clear();

      await c.read(sessionControllerProvider.notifier).eraseEverything();
      await _until(() => spy.wipes == 1 && stateOf(c) == CloudSyncState.live);
      await _until(() => secure.values['outflow.cloud.pendingWipe.u1'] == null);

      expect(spy.deletes, isEmpty, reason: 'el borrado local no se refleja doc a doc');
      final cloud = await cloudOf('u1').readAll();
      expect(cloud[LocalStore.movementsBox] ?? {}, isEmpty);
      expect(cloud[LocalStore.accountsBox]!.keys.toSet(), {kDefaultAccountId});
      expect(cloud[LocalStore.categoriesBox]!.keys.toSet(), {for (final c in defaultCategories()) c.id});
      expect(cloud[LocalStore.settingsBox]!['wallet.settings']!['onboardingDone'], isFalse);
      final resetAt = await cloudOf('u1').resetAt();
      expect(resetAt, isNotNull);
      expect(DateTime.parse(secure.values['outflow.cloud.loadedAt.u1']!).isBefore(resetAt!), isFalse);
      expect(_box(store, LocalStore.movementsBox), isEmpty);
    });

    test('borrar sin haber migrado (preguntando) no toca la nube y vuelve a decidir', () async {
      await owner('u1');
      await store.write(LocalStore.movementsBox, 'm-local', _mov('m-local', 10).toJson());
      await cloudOf('u1').uploadAll({
        LocalStore.movementsBox: {'m-cloud': _mov('m-cloud', 20).toJson()},
      });
      final c = ProviderContainer(overrides: session(FakeAuth(current: gabriel)));
      addTearDown(c.dispose);
      c.listen(cloudSyncProvider, (_, _) {});
      await _until(() => stateOf(c) == CloudSyncState.needsChoice);

      await c.read(sessionControllerProvider.notifier).eraseEverything();
      await _until(() => stateOf(c) == CloudSyncState.live);
      final spy = spyFor('u1');
      expect(spy.wipes, 0);
      expect(spy.uploads, isEmpty);
      final cloud = await cloudOf('u1').readAll();
      expect(cloud[LocalStore.movementsBox]!.keys.toSet(), {'m-cloud'});
      for (final box in kSyncedBoxes) {
        expect(_box(store, box), cloud[box] ?? {}, reason: box);
      }
      expect(secure.values['outflow.cloud.pendingWipe.u1'], isNull);
    });

    test('si el borrado local falla, no se sube la wallet a medio borrar', () async {
      await owner('u1');
      await store.write(LocalStore.movementsBox, 'm1', _mov('m1', 1000).toJson());
      final settings = _FailingSettings(store);
      final c = ProviderContainer(overrides: [
        ...session(FakeAuth(current: gabriel)),
        walletSettingsRepositoryProvider.overrideWithValue(settings),
      ]);
      addTearDown(c.dispose);
      c.listen(cloudSyncProvider, (_, _) {});
      await _until(() => stateOf(c) == CloudSyncState.live);
      final spy = spyFor('u1')..uploads.clear();
      settings.fail = true;

      await expectLater(c.read(sessionControllerProvider.notifier).eraseEverything(), throwsA(isA<StateError>()));
      await _until(() => stateOf(c) == CloudSyncState.unavailable);
      await pumpEventQueue();
      expect(spy.uploads, isEmpty);
    });

    test('reinstalar: tras descargar una wallet ya configurada, la sesión no repite la configuración', () async {
      await cloudOf('u1').uploadAll({
        LocalStore.settingsBox: {
          'wallet.settings': {'currency': 'PEN', 'onboardingDone': true},
        },
        LocalStore.movementsBox: {'m1': _mov('m1', 1).toJson()},
      });
      final c = ProviderContainer(overrides: session(FakeAuth(current: gabriel)));
      addTearDown(c.dispose);
      c.listen(cloudSyncProvider, (_, _) {});
      await _until(() => stateOf(c) == CloudSyncState.live);
      await _until(() => c.read(sessionControllerProvider) is! NeedsOnboarding && c.read(sessionControllerProvider) is! SessionLoading);
      expect(c.read(sessionControllerProvider), isA<Ready>());
    });
  });

  group('subida interrumpida y otros detalles', () {
    test('I1: tras una primera subida cortada, lo editado y borrado después gana y no se pregunta', () async {
      await owner('u1');
      await store.write(LocalStore.movementsBox, 'm1', _mov('m1', 1000).toJson());
      await store.write(LocalStore.movementsBox, 'm2', _mov('m2', 2000).toJson());
      spyFor('u1').hangAfterUpload = true;
      final c = open(gabriel, timeout: const Duration(milliseconds: 300));
      await _until(() => stateOf(c) == CloudSyncState.unavailable, reason: 'unavailable');
      expect(secure.values.keys.where((k) => k.startsWith('outflow.cloud.migrated')), isEmpty);
      expect((await cloudOf('u1').readAll())[LocalStore.movementsBox]!.keys.toSet(), {'m1', 'm2'});

      await store.write(LocalStore.movementsBox, 'm1', _mov('m1', 1111).toJson());
      await store.remove(LocalStore.movementsBox, 'm2');
      spyFor('u1').hangAfterUpload = false;

      final seen = <CloudSyncState>[];
      c.listen(cloudSyncStateProvider, (_, n) => seen.add(n));
      await c.read(cloudSyncProvider.notifier).retry();
      await _until(() => stateOf(c) == CloudSyncState.live, reason: 'live');
      expect(seen, isNot(contains(CloudSyncState.needsChoice)));
      final cloud = (await cloudOf('u1').readAll())[LocalStore.movementsBox]!;
      expect(cloud.keys.toSet(), {'m1'});
      expect((cloud['m1']!['amount'] as Map)['minor'], 1111);
      expect(_box(store, LocalStore.movementsBox).keys.toSet(), {'m1'});
      expect(secure.values['outflow.cloud.migrated.u1'], isNotNull);
      expect(secure.values.keys.where((k) => k.startsWith('outflow.cloud.uploading')), isEmpty);
    });

    test('M1: las fechas guardadas van en UTC', () async {
      await migrated('u1');
      expect(secure.values['outflow.cloud.loadedAt.u1'], endsWith('Z'));
    });

    test('M5: un teléfono ya migrado que abre sin red entra en vivo', () async {
      final c = await migrated('u1');
      c.dispose();
      spyFor('u1').resetOffline = true;
      final c2 = open(gabriel);
      await _until(() => stateOf(c2) == CloudSyncState.live, reason: 'live sin red');
    });

    test('M7: borrar los ajustes en la nube conserva lo del dispositivo', () async {
      final c = await migrated('u1');
      await store.write(LocalStore.settingsBox, 'wallet.settings',
          const WalletSettings(ownerUid: 'u1', faceIdEnabled: true, onboardingDone: true).toJson());
      await pumpEventQueue();
      await cloudOf('u1').delete(LocalStore.settingsBox, 'wallet.settings');
      await pumpEventQueue(times: 200);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final settings = store.read(LocalStore.settingsBox, 'wallet.settings');
      expect(settings, isNotNull);
      expect(settings!['ownerUid'], 'u1');
      expect(settings['faceIdEnabled'], isTrue);
      expect(stateOf(c), CloudSyncState.live);
    });

    test('M2: si la nube no coincide con lo mostrado, no se borra nada', () async {
      final c = await migrated('u1');
      final n = c.read(cloudSyncProvider.notifier);
      expect(await n.willEraseCloud(), isTrue);
      expect(await n.beginErase(DateTime.now(), false), isFalse);
      expect(spyFor('u1').wipes, 0);
      expect(stateOf(c), CloudSyncState.live);
    });
  });
}

/// Ajustes de Hive que pueden fallar al guardar (borrado local a medias).
class _FailingSettings extends HiveWalletSettingsRepository {
  _FailingSettings(super.store);
  bool fail = false;

  @override
  Future<void> save(WalletSettings settings) {
    if (fail) throw StateError('disco lleno');
    return super.save(settings);
  }
}

/// Un valor que el test cambia a mano (para simular cerrar sesión).
class StateNotifierLike {
  StateNotifierLike(Account? initial) : provider = NotifierProvider<AccountHolder, Account?>(() => AccountHolder(initial));
  final NotifierProvider<AccountHolder, Account?> provider;
}

class AccountHolder extends Notifier<Account?> {
  AccountHolder(this._initial);
  final Account? _initial;
  @override
  Account? build() => _initial;
  void set(Account? a) => state = a;
}
