import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/di/core_providers.dart';
import '../domain/process_captures.dart';

/// Último texto recibido con clave válida, solo en memoria, para el modo
/// diagnóstico de la guía. Se borra al salir de la guía y al borrar los datos.
final lastCaptureProvider = NotifierProvider<LastCapture, CaptureEvent?>(LastCapture.new);

class LastCapture extends Notifier<CaptureEvent?> {
  @override
  CaptureEvent? build() => null;

  void set(CaptureEvent? event) => state = event;
}

final captureKeyStoreProvider = Provider<CaptureKeyStore>(
  (ref) => CaptureKeyStore(ref.watch(secureStorageProvider)),
);

/// Clave por instalación que acompaña a cada enlace `outflow://captura`. Sin ella,
/// cualquier página o app podría meter textos falsos en la bandeja. Vive en el
/// llavero del sistema y la guía deja copiarla dentro de la URL del atajo.
class CaptureKeyStore {
  CaptureKeyStore(this._secure);

  static const storageKey = 'outflow.capture.key';

  final FlutterSecureStorage _secure;
  String? _cached;

  Future<String>? _loading;

  /// Una sola carga a la vez: llamadas simultáneas comparten la misma clave.
  Future<String> key() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<String> _load() async {
    String? stored;
    try {
      stored = await _secure.read(key: storageKey);
    } catch (_) {
      stored = null;
    }
    if (stored != null && stored.isNotEmpty) return _cached = stored;
    final fresh = _generate();
    try {
      await _secure.write(key: storageKey, value: fresh);
    } catch (_) {
      // Sin llavero la clave dura lo que dure la app: el atajo tendrá que copiarse de nuevo.
    }
    return _cached = fresh;
  }

  /// Olvida la clave: la siguiente será otra y el atajo viejo deja de valer.
  Future<void> reset() async {
    _cached = null;
    _loading = null;
    try {
      await _secure.delete(key: storageKey);
    } catch (_) {
      // Sin nada que borrar.
    }
  }

  static String _generate() {
    final random = Random.secure();
    return [for (var i = 0; i < 24; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }
}
