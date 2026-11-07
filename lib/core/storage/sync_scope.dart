import 'local_store.dart';

/// Cajas cuyos documentos se reflejan por completo en la nube.
const kSyncedBoxes = [
  LocalStore.movementsBox,
  LocalStore.accountsBox,
  LocalStore.subscriptionsBox,
  LocalStore.merchantsBox,
  LocalStore.categoriesBox,
];

/// Claves de la caja `settings` que se sincronizan (`account.preview` y
/// el resto son solo de este dispositivo).
const kSyncedSettings = {'wallet.settings', 'notifications.globalRule', 'capture.sources'};

/// Campos de `wallet.settings` que pertenecen al dispositivo, no a la wallet.
const _deviceOnlyWalletFields = ['faceIdEnabled', 'ownerUid'];

bool _isWalletSettings(String box, String id) => box == LocalStore.settingsBox && id == 'wallet.settings';

/// ¿Se sincroniza este documento con la nube?
bool isSynced(String box, String id) =>
    box == LocalStore.settingsBox ? kSyncedSettings.contains(id) : kSyncedBoxes.contains(box);

/// Documento local -> nube: quita lo que es solo del dispositivo.
Map<String, Object?> toCloud(String box, String id, Map<String, Object?> json) {
  if (!_isWalletSettings(box, id)) return json;
  return {
    for (final e in json.entries)
      if (!_deviceOnlyWalletFields.contains(e.key)) e.key: e.value,
  };
}

/// Documento de la nube -> local: conserva los campos del dispositivo que
/// ya había en [local].
Map<String, Object?> fromCloud(String box, String id, Map<String, Object?> remote, Map<String, Object?>? local) {
  if (!_isWalletSettings(box, id) || local == null) return remote;
  return {
    ...remote,
    for (final k in _deviceOnlyWalletFields)
      if (local.containsKey(k)) k: local[k],
  };
}
