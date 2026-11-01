import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  static const movementsBox = 'movements';
  static const categoriesBox = 'categories';

  static const _keyName = 'outflow.hive.key';

  final Map<String, Box<String>> _boxes;

  /// Cajas sin cifrar en [Hive.init] (tests).
  @visibleForTesting
  static Future<LocalStore> openUnencrypted() async {
    final boxes = <String, Box<String>>{};
    for (final name in const [subscriptionsBox, merchantsBox, settingsBox, movementsBox, categoriesBox]) {
      boxes[name] = await Hive.openBox<String>(name);
    }
    return LocalStore._(boxes);
  }

  static const _names = [subscriptionsBox, merchantsBox, settingsBox, movementsBox, categoriesBox];

  static Future<LocalStore> open(FlutterSecureStorage secure) async {
    await Hive.initFlutter('outflow');
    return openWith(secure);
  }

  /// Abre las cajas cifradas. Si la clave no se puede leer (p. ej. Samsung
  /// restauró una copia de una instalación anterior cuya clave del Keystore
  /// ya no existe) o las cajas no se descifran, esos datos son irrecuperables:
  /// se empieza de cero con una clave nueva en vez de dejar la app colgada.
  @visibleForTesting
  static Future<LocalStore> openWith(FlutterSecureStorage secure) async {
    try {
      return await _openEncrypted(await _encryptionKey(secure));
    } catch (e) {
      debugPrint('Almacén local ilegible, se empieza de cero: $e');
      try {
        await secure.deleteAll();
      } catch (e) {
        debugPrint('No se pudo limpiar el llavero: $e');
      }
      for (final name in _names) {
        try {
          await Hive.deleteBoxFromDisk(name);
        } catch (_) {
          // Caja que no existía o ya cerrada.
        }
      }
      return _openEncrypted(await _encryptionKey(secure));
    }
  }

  static Future<LocalStore> _openEncrypted(List<int> key) async {
    final cipher = HiveAesCipher(key);
    final boxes = <String, Box<String>>{};
    for (final name in _names) {
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

  /// Escritura en bloque (una sola ráfaga de cambios para los observadores).
  Future<void> writeAll(String box, Map<String, Map<String, Object?>> docs) =>
      _box(box).putAll({for (final e in docs.entries) e.key: jsonEncode(e.value)});

  Future<void> removeAll(String box, Iterable<String> ids) => _box(box).deleteAll(ids);

  /// Vacía todas las cajas (la clave de cifrado se conserva).
  Future<void> clearAll() async {
    for (final box in _boxes.values) {
      await box.clear();
    }
  }

  /// Emite el contenido actual y lo re-emite en cada cambio de la caja.
  Stream<List<Map<String, Object?>>> watchAll(String box) async* {
    yield readAll(box);
    yield* _box(box).watch().map((_) => readAll(box));
  }
}
