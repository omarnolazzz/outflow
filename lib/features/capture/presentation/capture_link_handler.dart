import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/capture_inbox.dart';
import '../data/capture_key.dart';
import '../domain/capture_link.dart';
import 'capture_providers.dart';

/// Texto inventado con el que la guía comprueba la lectura sin un correo real.
const kCaptureSampleText =
    'Scotiabank: Consumo de S/ 45.50 en BODEGA EJEMPLO con tu tarjeta ****1234. Operación 99887766. Fecha 20/10/2026.';

final captureLinkHandlerProvider = Provider<CaptureLinkHandler>(CaptureLinkHandler.new);

/// Recibe `outflow://captura`. Un enlace válido solo deja el texto en la bandeja y
/// pide procesarla: nunca abre un formulario ni muestra nada. Si la app está
/// bloqueada, el evento espera en la bandeja y `captureSyncProvider` lo procesa al
/// desbloquear. El texto no se escribe en ningún registro.
class CaptureLinkHandler {
  CaptureLinkHandler(this._ref);
  final Ref _ref;

  /// true si el enlace era válido y se guardó; con clave mala, nada de nada.
  Future<bool> handle(Uri uri) async {
    if (uri.scheme != 'outflow' || uri.host != 'captura') return false;
    try {
      final key = await _ref.read(captureKeyStoreProvider).key();
      final event = parseCaptureLink(uri, expectedKey: key, now: DateTime.now());
      if (event == null) return false;
      await _ref.read(captureInboxProvider).add(event);
      _ref.read(lastCaptureProvider.notifier).set(event);
      // Sin esperar: bloqueada, no hace nada y lo recoge el desbloqueo.
      _ref.read(captureRunnerProvider).run().ignore();
      return true;
    } catch (e) {
      // Solo el tipo: el error podría citar el texto del correo.
      debugPrint('No se pudo guardar la captura por enlace: ${e.runtimeType}');
      return false;
    }
  }
}
