import '../../../core/storage/local_store.dart';
import '../../../core/storage/sync_scope.dart';
import '../../account/data/preview_auth_service.dart';
import '../../wallet/domain/default_categories.dart';
import '../../wallet/domain/wallet_account.dart';

/// Documentos de una wallet: caja -> id -> json.
typedef WalletDocs = Map<String, Map<String, Map<String, Object?>>>;

/// Qué hacer la primera vez que una cuenta entra en este teléfono.
enum MigrationCase { upload, download, ask, foreign }

const _walletSettingsId = 'wallet.settings';

/// Conjuntos de `wallet.settings` que se unen al unir dos teléfonos.
const _unionLists = ['deletedChargeIds', 'dismissedSplitMatchIds'];
const _unionMaps = ['splitAccountIds'];

final Set<String> _defaultCategoryIds = {for (final c in defaultCategories()) c.id};

/// Solo lo predeterminado: "Mi cuenta" sin saldo inicial, las categorías por
/// defecto y ningún movimiento, suscripción ni comercio propio. Los ajustes
/// no cuentan.
bool isEffectivelyEmpty(WalletDocs local) {
  if ((local[LocalStore.movementsBox] ?? const {}).isNotEmpty) return false;
  if ((local[LocalStore.subscriptionsBox] ?? const {}).isNotEmpty) return false;
  for (final e in (local[LocalStore.accountsBox] ?? const <String, Map<String, Object?>>{}).entries) {
    if (e.key != kDefaultAccountId) return false;
    final initial = e.value['initialMinor'];
    if (initial != null && initial != 0) return false;
  }
  for (final id in (local[LocalStore.categoriesBox] ?? const <String, Map<String, Object?>>{}).keys) {
    if (!_defaultCategoryIds.contains(id)) return false;
  }
  for (final id in (local[LocalStore.merchantsBox] ?? const <String, Map<String, Object?>>{}).keys) {
    if (id.startsWith('custom.')) return false;
  }
  return true;
}

/// Lo local es de otra cuenta (ni sin dueño, ni de la vista previa, ni de [uid]).
bool isForeignOwner(String? localOwner, String uid) =>
    localOwner != null && localOwner != uid && localOwner != PreviewAuthService.uid;

bool _cloudIsEmpty(WalletDocs cloud) => cloud.values.every((b) => b.isEmpty);

/// Cada documento sincronizado de [local] ya está igual en [cloud].
bool _localInCloud(WalletDocs local, WalletDocs cloud) {
  for (final b in local.entries) {
    for (final d in b.value.entries) {
      if (!isSynced(b.key, d.key)) continue;
      final remote = cloud[b.key]?[d.key];
      if (remote == null || !jsonEquals(toCloud(b.key, d.key, d.value), remote)) return false;
    }
  }
  return true;
}

/// - lo local de otra cuenta → [MigrationCase.foreign];
/// - nube vacía → [MigrationCase.upload] (también con lo local vacío: subir lo
///   predeterminado no pierde nada, y descargar una nube vacía lo borraría);
/// - local vacío, o todo lo local ya está en la nube → [MigrationCase.download];
/// - ambos con datos → [MigrationCase.ask].
MigrationCase decideMigration({
  required WalletDocs local,
  required WalletDocs cloud,
  required String uid,
  String? localOwner,
}) {
  if (isForeignOwner(localOwner, uid)) return MigrationCase.foreign;
  if (_cloudIsEmpty(cloud)) return MigrationCase.upload;
  if (isEffectivelyEmpty(local) || _localInCloud(local, cloud)) return MigrationCase.download;
  return MigrationCase.ask;
}

/// Lo que "Unir" sube: solo los ids que no están en la nube (si un id está en
/// ambos lados, gana la nube). En `wallet.settings` gana la nube salvo los
/// conjuntos, que se unen, y `walletStartedAt`, que es el más antiguo;
/// `capture.sources` se une (gana la nube en la misma fuente). Los documentos
/// salen sin los campos del dispositivo ([toCloud]).
WalletDocs mergeForUpload({required WalletDocs local, required WalletDocs cloud}) {
  final out = <String, Map<String, Map<String, Object?>>>{};
  void add(String box, String id, Map<String, Object?> json) => (out[box] ??= {})[id] = json;

  for (final b in local.entries) {
    for (final d in b.value.entries) {
      if (!isSynced(b.key, d.key)) continue;
      final mine = toCloud(b.key, d.key, d.value);
      final theirs = cloud[b.key]?[d.key];
      if (theirs == null) {
        add(b.key, d.key, mine);
        continue;
      }
      if (b.key != LocalStore.settingsBox) continue;
      final merged = switch (d.key) {
        _walletSettingsId => _mergeWalletSettings(mine, theirs),
        'capture.sources' => {...mine, ...theirs},
        _ => theirs,
      };
      if (!jsonEquals(merged, theirs)) add(b.key, d.key, merged);
    }
  }
  return out;
}

Map<String, Object?> _mergeWalletSettings(Map<String, Object?> mine, Map<String, Object?> theirs) {
  final out = {...theirs};
  for (final k in _unionLists) {
    final union = {...?(mine[k] as List?)?.cast<String>(), ...?(theirs[k] as List?)?.cast<String>()};
    if (union.isNotEmpty || out.containsKey(k)) out[k] = union.toList()..sort();
  }
  for (final k in _unionMaps) {
    final union = {...?(mine[k] as Map?)?.cast<String, Object?>(), ...?(theirs[k] as Map?)?.cast<String, Object?>()};
    if (union.isNotEmpty || out.containsKey(k)) out[k] = union;
  }
  // Un inicio nulo es "sin fijar": no deja fuera nada del otro teléfono.
  final m = _date(mine['walletStartedAt']);
  final t = _date(theirs['walletStartedAt']);
  if (m != null && (t == null || m.isBefore(t))) out['walletStartedAt'] = mine['walletStartedAt'];
  return out;
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Igualdad profunda de valores JSON (mapas sin importar el orden de claves).
bool jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key) || !jsonEquals(e.value, b[e.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
