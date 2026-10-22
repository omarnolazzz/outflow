import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/apple_pay_link.dart';

/// Enlaces `outflow://…` que abren la app (el inicial y los que llegan con
/// ella abierta). En la web no hay ninguno.
final incomingLinksProvider = Provider<Stream<Uri>>((ref) {
  if (kIsWeb) return const Stream.empty();
  return AppLinks().uriLinkStream;
});

/// Guarda el último gasto llegado por enlace mientras la app está bloqueada y
/// lo entrega una sola vez al desbloquear.
class PendingLink {
  MovementDraft? _pending;

  /// Devuelve el borrador para abrirlo ya (si la app está lista) o lo guarda.
  MovementDraft? offer(MovementDraft draft, {required bool ready}) {
    if (ready) {
      _pending = null;
      return draft;
    }
    _pending = draft;
    return null;
  }

  /// Al desbloquear: el borrador pendiente, una vez.
  MovementDraft? onReady() {
    final d = _pending;
    _pending = null;
    return d;
  }
}
