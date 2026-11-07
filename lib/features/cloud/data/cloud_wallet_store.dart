import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/storage/local_store.dart';
import '../../../core/storage/sync_scope.dart';

/// Un documento de la wallet en la nube. `json == null` significa borrado.
class CloudDoc {
  const CloudDoc({required this.box, required this.id, required this.json});
  final String box;
  final String id;
  final Map<String, Object?>? json;
}

/// Cambios de una caja con los metadatos de Firestore.
class CloudSnapshot {
  const CloudSnapshot({required this.changes, required this.fromCache, required this.hasPendingWrites});
  final List<CloudDoc> changes;
  final bool fromCache;
  final bool hasPendingWrites;
}

/// La nube no respondió. [permissionDenied] distingue reglas/sesión de red.
class CloudUnavailable implements Exception {
  const CloudUnavailable({required this.permissionDenied, this.cause});
  final bool permissionDenied;
  final Object? cause;

  @override
  String toString() => 'CloudUnavailable(permissionDenied: $permissionDenied, $cause)';
}

/// Almacén remoto de la wallet de una cuenta: `wallets/{uid}/{caja}/{id}`.
abstract interface class CloudWalletStore {
  Future<void> put(String box, String id, Map<String, Object?> json);
  Future<void> delete(String box, String id);

  /// caja -> id -> json, solo del servidor.
  Future<Map<String, Map<String, Map<String, Object?>>>> readAll();

  /// Sube todo en lotes de 400; termina con la confirmación del servidor.
  Future<void> uploadAll(Map<String, Map<String, Map<String, Object?>>> docs);

  Stream<CloudSnapshot> watch(String box);
  Future<DateTime?> resetAt();

  /// Lo más reciente del servidor escrito por otra instalación: el `updatedAt`
  /// de un documento ajeno o el `resetAt` de la raíz (null si no hay nada).
  Future<DateTime?> lastChangeAt();

  /// Borra todas las colecciones y escribe `resetAt`.
  Future<void> wipe(DateTime at);

  /// Anota [token] (el id de una instalación) entre las que ya migraron esta
  /// wallet, en el documento raíz. Un `wipe` reinicia la lista.
  Future<void> markMigratedBy(String token);

  /// Las instalaciones que anotaron su migración.
  Future<Set<String>> migratedBy();

  /// Los documentos del servidor que firmó [writer] (caja -> ids) y si hay
  /// alguno de otra instalación o sin firma (`foreign`).
  Future<({Map<String, Set<String>> mine, bool foreign})> writtenBy(String writer);
}

const _batchSize = 400;

/// Cajas que viven en la nube (la de ajustes solo con [kSyncedSettings]).
final List<String> _allBoxes = [...kSyncedBoxes, LocalStore.settingsBox];

/// Firestore no admite en claves de mapa `.`, `/`, vacías ni que empiecen
/// por `__`. Se codifican con porcentaje, de forma reversible.
String _encodeKey(String k) {
  if (k.isEmpty) return '%';
  var s = k.replaceAll('%', '%25').replaceAll('.', '%2E').replaceAll('/', '%2F');
  if (s.startsWith('__')) s = '%5F${s.substring(1)}';
  return s;
}

String _decodeKey(String k) {
  if (k == '%') return '';
  const map = {'%5F': '_', '%2E': '.', '%2F': '/', '%25': '%'};
  return k.replaceAllMapped(RegExp('%(5F|2E|2F|25)'), (m) => map[m[0]]!);
}

Object? _walk(Object? v, String Function(String) key) {
  if (v is Map) return {for (final e in v.entries) key(e.key as String): _walk(e.value, key)};
  if (v is List) return [for (final x in v) _walk(x, key)];
  return v;
}

Map<String, Object?> _decodeJson(Object? raw) => (_walk(raw, _decodeKey) as Map).cast<String, Object?>();

class FirestoreCloudWalletStore implements CloudWalletStore {
  FirestoreCloudWalletStore(this._db, this._uid, {this.writer});
  final FirebaseFirestore _db;
  final String _uid;

  /// Id de la instalación que escribe: cada documento lo lleva en `writer`.
  final String? Function()? writer;

  static const _server = GetOptions(source: Source.server);

  DocumentReference<Map<String, dynamic>> get _root => _db.collection('wallets').doc(_uid);
  CollectionReference<Map<String, dynamic>> _col(String box) => _root.collection(box);

  void _check(String box, String id) {
    if (!_allBoxes.contains(box)) throw ArgumentError.value(box, 'box', 'Caja no sincronizada');
    if (!isSynced(box, id)) throw ArgumentError.value(id, 'id', 'Documento no sincronizado');
  }

  Map<String, Object?> _data(Map<String, Object?> json) {
    final writer = this.writer?.call();
    return {
      'json': _walk(json, _encodeKey),
      'updatedAt': FieldValue.serverTimestamp(),
      'writer': ?writer,
    };
  }

  Never _unavailable(FirebaseException e) =>
      throw CloudUnavailable(permissionDenied: e.code == 'permission-denied', cause: e);

  /// Traduce los errores de Firestore de una escritura suelta.
  Future<void> _write(Future<void> Function() f) async {
    try {
      await f();
    } on FirebaseException catch (e) {
      _unavailable(e);
    }
  }

  @override
  Future<void> put(String box, String id, Map<String, Object?> json) {
    _check(box, id);
    return _write(() => _col(box).doc(id).set(_data(json)));
  }

  @override
  Future<void> delete(String box, String id) => _write(() => _col(box).doc(id).delete());

  @override
  Future<Map<String, Map<String, Map<String, Object?>>>> readAll() async {
    final out = <String, Map<String, Map<String, Object?>>>{};
    try {
      for (final box in _allBoxes) {
        final snap = await _col(box).get(_server);
        if (snap.metadata.isFromCache) throw const CloudUnavailable(permissionDenied: false);
        out[box] = {
          for (final d in snap.docs)
            if (d.data()['json'] != null && isSynced(box, d.id)) d.id: _decodeJson(d.data()['json']),
        };
      }
    } on FirebaseException catch (e) {
      debugPrint('Lectura de la wallet sin servidor: $e');
      _unavailable(e);
    }
    return out;
  }

  @override
  Future<void> uploadAll(Map<String, Map<String, Map<String, Object?>>> docs) async {
    final entries = [
      for (final b in docs.entries)
        for (final d in b.value.entries) (box: b.key, id: d.key, json: d.value),
    ];
    for (final e in entries) {
      _check(e.box, e.id);
    }
    try {
      for (var i = 0; i < entries.length; i += _batchSize) {
        final batch = _db.batch();
        for (final e in entries.skip(i).take(_batchSize)) {
          batch.set(_col(e.box).doc(e.id), _data(e.json));
        }
        await batch.commit();
      }
    } on FirebaseException catch (e) {
      _unavailable(e);
    }
  }

  @override
  Stream<CloudSnapshot> watch(String box) => _col(box).snapshots(includeMetadataChanges: true).map((snap) {
        return CloudSnapshot(
          changes: [
            for (final c in snap.docChanges)
              if (isSynced(box, c.doc.id))
                CloudDoc(
                  box: box,
                  id: c.doc.id,
                  json: c.type == DocumentChangeType.removed || c.doc.data()?['json'] == null
                      ? null
                      : _decodeJson(c.doc.data()!['json']),
                ),
          ],
          fromCache: snap.metadata.isFromCache,
          hasPendingWrites: snap.metadata.hasPendingWrites,
        );
      }).handleError((Object e) {
        // Un permiso denegado (reglas sin publicar) se distingue de la red.
        if (e is FirebaseException) _unavailable(e);
        throw e;
      });

  @override
  Future<DateTime?> resetAt() async {
    try {
      final snap = await _root.get(_server);
      final v = snap.data()?['resetAt'];
      return v is String ? DateTime.parse(v) : null;
    } on FirebaseException catch (e) {
      _unavailable(e);
    }
  }

  @override
  Future<DateTime?> lastChangeAt() async {
    DateTime? latest;
    void see(DateTime? d) {
      if (d != null && (latest == null || d.isAfter(latest!))) latest = d;
    }

    final me = writer?.call();
    try {
      final reset = (await _root.get(_server)).data()?['resetAt'];
      if (reset is String) see(DateTime.tryParse(reset));
      for (final box in _allBoxes) {
        final snap = await _col(box).get(_server);
        if (snap.metadata.isFromCache) throw const CloudUnavailable(permissionDenied: false);
        for (final d in snap.docs) {
          // Lo que esta instalación encoló antes de borrar llega después, pero no es nuevo.
          if (me != null && d.data()['writer'] == me) continue;
          final updated = d.data()['updatedAt'];
          if (updated is Timestamp) see(updated.toDate());
        }
      }
    } on FirebaseException catch (e) {
      _unavailable(e);
    }
    return latest;
  }

  @override
  Future<void> markMigratedBy(String token) =>
      _write(() => _root.set({'migratedBy': FieldValue.arrayUnion([token])}, SetOptions(merge: true)));

  @override
  Future<Set<String>> migratedBy() async {
    try {
      final v = (await _root.get(_server)).data()?['migratedBy'];
      return v is List ? v.whereType<String>().toSet() : <String>{};
    } on FirebaseException catch (e) {
      _unavailable(e);
    }
  }

  @override
  Future<({Map<String, Set<String>> mine, bool foreign})> writtenBy(String writer) async {
    final mine = <String, Set<String>>{};
    var foreign = false;
    try {
      for (final box in _allBoxes) {
        final snap = await _col(box).get(_server);
        if (snap.metadata.isFromCache) throw const CloudUnavailable(permissionDenied: false);
        final ids = <String>{};
        for (final d in snap.docs) {
          if (!isSynced(box, d.id)) continue;
          if (d.data()['writer'] == writer) {
            ids.add(d.id);
          } else {
            foreign = true;
          }
        }
        mine[box] = ids;
      }
    } on FirebaseException catch (e) {
      _unavailable(e);
    }
    return (mine: mine, foreign: foreign);
  }

  @override
  Future<void> wipe(DateTime at) async {
    try {
      for (final box in _allBoxes) {
        final snap = await _col(box).get(_server);
        if (snap.metadata.isFromCache) throw const CloudUnavailable(permissionDenied: false);
        final refs = snap.docs.map((d) => d.reference).toList();
        for (var i = 0; i < refs.length; i += _batchSize) {
          final batch = _db.batch();
          for (final r in refs.skip(i).take(_batchSize)) {
            batch.delete(r);
          }
          await batch.commit();
        }
      }
      await _root.set({'resetAt': at.toUtc().toIso8601String()});
    } on FirebaseException catch (e) {
      _unavailable(e);
    }
  }
}
