import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:outflow/core/storage/local_store.dart';
import 'package:outflow/core/storage/sync_scope.dart';

void main() {
  late Directory dir;
  late LocalStore store;
  late List<StoreChange> seen;
  late StreamSubscription<StoreChange> sub;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('outflow_hooks');
    Hive.init(dir.path);
    store = await LocalStore.openUnencrypted();
    seen = [];
    sub = store.changes.listen(seen.add);
  });

  tearDown(() async {
    await sub.cancel();
    await Hive.deleteFromDisk();
    dir.deleteSync(recursive: true);
  });

  test('write, remove y writeAll emiten 1, 1 y 3 cambios', () async {
    await store.write(LocalStore.movementsBox, 'a', {'id': 'a'});
    await pumpEventQueue();
    expect(seen, hasLength(1));
    expect(seen.single.box, LocalStore.movementsBox);
    expect(seen.single.id, 'a');
    expect(seen.single.json, {'id': 'a'});

    seen.clear();
    await store.remove(LocalStore.movementsBox, 'a');
    await pumpEventQueue();
    expect(seen, hasLength(1));
    expect(seen.single.json, isNull);

    seen.clear();
    await store.writeAll(LocalStore.movementsBox, {
      for (final id in ['x', 'y', 'z']) id: {'id': id},
    });
    await pumpEventQueue();
    expect(seen.map((c) => c.id), ['x', 'y', 'z']);
  });

  test('removeAll emite un borrado por id', () async {
    await store.writeAll(LocalStore.movementsBox, {'x': {'id': 'x'}, 'y': {'id': 'y'}});
    seen.clear();
    await store.removeAll(LocalStore.movementsBox, ['x', 'y']);
    await pumpEventQueue();
    expect(seen.map((c) => c.id), ['x', 'y']);
    expect(seen.every((c) => c.json == null), isTrue);
  });

  test('applyRemote y applyRemoteAll cambian los datos sin emitir', () async {
    await store.applyRemote(LocalStore.movementsBox, 'a', {'id': 'a'});
    await store.applyRemoteAll(LocalStore.movementsBox, {'b': {'id': 'b'}, 'c': {'id': 'c'}});
    expect(store.readAll(LocalStore.movementsBox), hasLength(3));
    await store.applyRemote(LocalStore.movementsBox, 'a', null);
    await store.applyRemoteAll(LocalStore.movementsBox, {'b': null});
    expect(store.read(LocalStore.movementsBox, 'a'), isNull);
    expect(store.read(LocalStore.movementsBox, 'b'), isNull);
    expect(store.read(LocalStore.movementsBox, 'c'), isNotNull);
    await pumpEventQueue();
    expect(seen, isEmpty);
  });

  test('clearAll emite un borrado por cada id existente', () async {
    await store.write(LocalStore.movementsBox, 'm1', {'id': 'm1'});
    await store.write(LocalStore.accountsBox, 'a1', {'id': 'a1'});
    await store.write(LocalStore.accountsBox, 'a2', {'id': 'a2'});
    seen.clear();
    await store.clearAll();
    await pumpEventQueue();
    expect(seen.map((c) => '${c.box}/${c.id}').toSet(), {'movements/m1', 'accounts/a1', 'accounts/a2'});
    expect(seen, hasLength(3));
    expect(seen.every((c) => c.json == null), isTrue);
    expect(store.readAll(LocalStore.accountsBox), isEmpty);
  });

  test('isSynced distingue lo que sube a la nube', () {
    expect(isSynced('settings', 'account.preview'), isFalse);
    expect(isSynced('settings', 'wallet.settings'), isTrue);
    expect(isSynced('settings', 'capture.sources'), isTrue);
    expect(isSynced('movements', 'x'), isTrue);
  });

  test('toCloud quita los campos del dispositivo y fromCloud conserva los locales', () {
    final cloud = toCloud('settings', 'wallet.settings', {'currency': 'PEN', 'faceIdEnabled': true, 'ownerUid': 'u1'});
    expect(cloud, {'currency': 'PEN'});

    final merged = fromCloud('settings', 'wallet.settings', {'currency': 'USD'}, {'currency': 'PEN', 'faceIdEnabled': true, 'ownerUid': 'u1'});
    expect(merged['currency'], 'USD');
    expect(merged['faceIdEnabled'], true);
    expect(merged['ownerUid'], 'u1');

    expect(toCloud('movements', 'm', {'faceIdEnabled': 1}), {'faceIdEnabled': 1});
  });
}
