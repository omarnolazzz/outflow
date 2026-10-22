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

/// Guarda los gastos llegados por enlace mientras la app está bloqueada (en
/// orden, sin perder ninguno) y los entrega una sola vez al desbloquear.
class PendingLink {
  final _pending = <MovementDraft>[];

  /// Devuelve el borrador para abrirlo ya (si la app está lista) o lo guarda.
  MovementDraft? offer(MovementDraft draft, {required bool ready}) {
    if (ready) return draft;
    _pending.add(draft);
    return null;
  }

  /// Al desbloquear: todos los pendientes, una vez.
  List<MovementDraft> takeAll() {
    final all = List.of(_pending);
    _pending.clear();
    return all;
  }
}
