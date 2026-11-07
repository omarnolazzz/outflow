import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:outflow/features/cloud/data/cloud_wallet_store.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreCloudWalletStore store;

  setUp(() {
    db = FakeFirebaseFirestore();
    store = FirestoreCloudWalletStore(db, 'u1');
  });

  test('put y readAll dan ida y vuelta con fechas y mapas anidados', () async {
    final json = <String, Object?>{
      'id': 'm1',
      'date': '2026-10-20T10:00:00.000',
      'amount': {'minor': 1250, 'currency': 'PEN'},
      'tags': ['a', 'b'],
      'note': null,
    };
    await store.put('movements', 'm1', json);
    final all = await store.readAll();
    expect(all['movements']!['m1'], json);
    final raw = await db.collection('wallets').doc('u1').collection('movements').doc('m1').get();
    expect(raw.data()!['updatedAt'], isNotNull);
  });

  test('claves con punto, barra, % o __ viajan sin pérdida', () async {
    final sources = <String, Object?>{
      'com.bcp.bank.bcp': 'acc1',
      'a/b': 'acc2',
      '__x__': 'acc3',
      '100%': 'acc4',
      '%5F%2E': 'acc6',
      '': 'acc5',
      'anidado': {'x.y': 1},
    };
    await store.put('settings', 'capture.sources', sources);
    final raw = await db.collection('wallets').doc('u1').collection('settings').doc('capture.sources').get();
    final stored = (raw.data()!['json'] as Map).keys.toList();
    expect(stored.any((k) => (k as String).contains('.') || k.contains('/') || k.startsWith('__') || k.isEmpty), isFalse);
    expect((await store.readAll())['settings']!['capture.sources'], sources);
  });

  test('delete lo quita y watch emite el borrado', () async {
    await store.put('accounts', 'a1', {'id': 'a1'});
    final events = <CloudSnapshot>[];
    final sub = store.watch('accounts').listen(events.add);
    await Future<void>.delayed(Duration.zero);
    await store.delete('accounts', 'a1');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(events.first.changes.single.id, 'a1');
    expect(events.first.changes.single.json, {'id': 'a1'});
    expect(events.last.changes.single.id, 'a1');
    expect(events.last.changes.single.json, isNull);
    expect((await store.readAll())['accounts'] ?? {}, isEmpty);
  });

  test('uploadAll sube 900 documentos', () async {
    final docs = {
      'movements': {for (var i = 0; i < 900; i++) 'm$i': <String, Object?>{'id': 'm$i'}},
      'settings': {
        'wallet.settings': <String, Object?>{'currency': 'PEN'},
      },
    };
    await store.uploadAll(docs);
    final all = await store.readAll();
    expect(all['movements']!.length, 900);
    expect(all['settings']!['wallet.settings'], {'currency': 'PEN'});
  });

  test('wipe vacía las colecciones y fija resetAt', () async {
    await store.put('movements', 'm1', {'id': 'm1'});
    await store.put('settings', 'wallet.settings', {'a': 1});
    expect(await store.resetAt(), isNull);
    final at = DateTime.utc(2026, 11, 7, 12);
    await store.wipe(at);
    final all = await store.readAll();
    expect(all.values.every((c) => c.isEmpty), isTrue);
    expect(await store.resetAt(), at);
  });

  test('wipe borra más de 400 documentos', () async {
    await store.uploadAll({
      'movements': {for (var i = 0; i < 850; i++) 'm$i': <String, Object?>{'id': 'm$i'}},
    });
    await store.wipe(DateTime.utc(2026, 11, 7));
    expect((await store.readAll())['movements'] ?? {}, isEmpty);
  });

  test('una clave de ajustes fuera de kSyncedSettings lanza ArgumentError', () async {
    expect(() => store.put('settings', 'account.preview', {'a': 1}), throwsArgumentError);
    expect(() => store.put('nope', 'x', {'a': 1}), throwsArgumentError);
  });

  test('la ruta usa el uid y otro uid no ve los datos', () async {
    await store.put('movements', 'm1', {'id': 'm1'});
    final other = FirestoreCloudWalletStore(db, 'u2');
    expect((await other.readAll())['movements'] ?? {}, isEmpty);
    final raw = await db.collection('wallets').doc('u1').collection('movements').doc('m1').get();
    expect(raw.exists, isTrue);
  });

  test('errores de Firestore se traducen a CloudUnavailable', () async {
    final ref = db.collection('wallets').doc('u1');
    whenCalling(Invocation.method(#get, [const GetOptions(source: Source.server)])).on(ref).thenThrow(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
    await expectLater(store.resetAt(), throwsA(isA<CloudUnavailable>().having((e) => e.permissionDenied, 'denied', true)));
  });

  test('unavailable no es permiso denegado', () async {
    final ref = db.collection('wallets').doc('u1');
    whenCalling(Invocation.method(#get, [const GetOptions(source: Source.server)])).on(ref).thenThrow(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
    await expectLater(store.resetAt(), throwsA(isA<CloudUnavailable>().having((e) => e.permissionDenied, 'denied', false)));
  });
}
