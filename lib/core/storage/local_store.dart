import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Persistencia local cifrada.
///
/// Cada caja de Hive guarda documentos JSON (String) por id; así no hace falta
/// generación de código ni TypeAdapters, y migrar el esquema es solo leer
/// campos opcionales. La clave AES-256 vive en el Keychain/Keystore.
class LocalStore {
  LocalStore._(this._boxes);

  static const subscriptionsBox = 'subscriptions';
  static const merchantsBox = 'merchants';
  static const settingsBox = 'settings';

  static const _keyName = 'outflow.hive.key';

  final Map<String, Box<String>> _boxes;

  static Future<LocalStore> open(FlutterSecureStorage secure) async {
    await Hive.initFlutter('outflow');
    final cipher = HiveAesCipher(await _encryptionKey(secure));
    final boxes = <String, Box<String>>{};
    for (final name in const [subscriptionsBox, merchantsBox, settingsBox]) {
      boxes[name] = await Hive.openBox<String>(name, encryptionCipher: cipher);
    }
    return LocalStore._(boxes);
  }

  static Future<List<int>> _encryptionKey(FlutterSecureStorage secure) async {
    final stored = await secure.read(key: _keyName);
    if (stored != null) return base64Url.decode(stored);
    final key = Hive.generateSecureKey();
    await secure.write(key: _keyName, value: base64UrlEncode(key));
    return key;
  }

  Box<String> _box(String name) => _boxes[name]!;

  Map<String, Object?>? read(String box, String id) {
    final raw = _box(box).get(id);
    return raw == null ? null : (jsonDecode(raw) as Map).cast<String, Object?>();
  }

  List<Map<String, Object?>> readAll(String box) => [
        for (final raw in _box(box).values) (jsonDecode(raw) as Map).cast<String, Object?>(),
      ];

  Future<void> write(String box, String id, Map<String, Object?> json) =>
      _box(box).put(id, jsonEncode(json));

  Future<void> remove(String box, String id) => _box(box).delete(id);

  /// Emite el contenido actual y lo re-emite en cada cambio de la caja.
  Stream<List<Map<String, Object?>>> watchAll(String box) async* {
    yield readAll(box);
    yield* _box(box).watch().map((_) => readAll(box));
  }
}
