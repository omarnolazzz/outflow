import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/storage/local_store.dart';

final captureSourcesRepositoryProvider = Provider<CaptureSourcesRepository>(
  (ref) => HiveCaptureSourcesRepository(ref.watch(localStoreProvider)),
);

/// A qué cuenta pertenece cada fuente de captura (paquete o remitente).
abstract interface class CaptureSourcesRepository {
  Map<String, String> read();
  Future<void> assign(String sourceKey, String accountId);
}

class HiveCaptureSourcesRepository implements CaptureSourcesRepository {
  HiveCaptureSourcesRepository(this._store);

  final LocalStore _store;
  static const _id = 'capture.sources';

  @override
  Map<String, String> read() {
    final json = _store.read(LocalStore.settingsBox, _id);
    return json == null ? const {} : json.map((k, v) => MapEntry(k, v as String));
  }

  @override
  Future<void> assign(String sourceKey, String accountId) =>
      _store.write(LocalStore.settingsBox, _id, {...read(), sourceKey: accountId});
}
