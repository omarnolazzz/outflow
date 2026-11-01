import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:outflow/core/storage/local_store.dart';

/// Llavero en memoria; con [brokenReads] > 0 las primeras lecturas fallan
/// como el Keystore de un Samsung con una copia restaurada.
class FakeSecure implements FlutterSecureStorage {
  FakeSecure({this.brokenReads = 0});
  int brokenReads;
  final values = <String, String>{};
  int deleteAllCalls = 0;

  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    if (brokenReads > 0) {
      brokenReads--;
      throw Exception('javax.crypto.BadPaddingException');
    }
    return values[key];
  }

  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> deleteAll({AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    deleteAllCalls++;
    values.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('outflow_store');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('con el llavero sano abre y conserva los datos entre aperturas', () async {
    final secure = FakeSecure();
    final store = await LocalStore.openWith(secure);
    await store.write(LocalStore.movementsBox, 'm1', {'id': 'm1'});
    await Hive.close();
    final again = await LocalStore.openWith(secure);
    expect(again.read(LocalStore.movementsBox, 'm1'), {'id': 'm1'});
  });

  test('si la clave no se puede leer, empieza de cero en vez de quedarse colgada', () async {
    final secure = FakeSecure(brokenReads: 1);
    final store = await LocalStore.openWith(secure);
    expect(store.readAll(LocalStore.movementsBox), isEmpty);
    expect(secure.deleteAllCalls, 1);
    expect(secure.values, isNotEmpty, reason: 'se guardó una clave nueva');
  });

  test('si las cajas no se descifran con la clave guardada, empieza de cero', () async {
    final secure = FakeSecure();
    final store = await LocalStore.openWith(secure);
    await store.write(LocalStore.movementsBox, 'm1', {'id': 'm1'});
    await Hive.close();
    // La clave del llavero cambió (otra instalación): las cajas ya no se leen.
    secure.values.updateAll((_, _) => 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=');
    final again = await LocalStore.openWith(secure);
    expect(again.readAll(LocalStore.movementsBox), isEmpty);
  });
}
