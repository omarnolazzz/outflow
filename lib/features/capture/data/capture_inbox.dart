import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/process_captures.dart';

export '../domain/process_captures.dart' show CaptureEvent;

final captureInboxProvider = Provider<CaptureInbox>((ref) => const CaptureInbox());

/// Textos bancarios pendientes de leer, de cualquier fuente: un archivo de líneas
/// JSON que escriben también los procesos nativos. El texto no se escribe en los
/// registros ni sale del teléfono, y el archivo se borra al terminar.
///
/// Para que un corte no pierda nada se procesa en dos pasos: [pending] aparta lo
/// que hay (lo que llegue luego sigue en la bandeja) y [commit], una vez guardados
/// los movimientos, lo borra. Tras un corte, [pending] vuelve a devolverlo.
class CaptureInbox {
  const CaptureInbox({this.directory});

  /// Carpeta de la bandeja (por defecto, los documentos de la app).
  final Future<Directory> Function()? directory;

  static const _fileName = 'capture_inbox.jsonl';
  static const _processingName = 'capture_inbox.processing';

  Future<File?> _file(String name) async {
    if (kIsWeb) return null;
    final dir = await (directory ?? getApplicationDocumentsDirectory)();
    return File('${dir.path}/$name');
  }

  Future<void> add(CaptureEvent event) async {
    final file = await _file(_fileName);
    await file?.writeAsString('${jsonEncode(event.toJson())}\n', mode: FileMode.append, flush: true);
  }

  /// Lo pendiente, sin borrarlo. Una línea ilegible se salta sin perder las demás.
  Future<List<CaptureEvent>> pending() async {
    final inbox = await _file(_fileName);
    final processing = await _file(_processingName);
    if (inbox == null || processing == null) return const [];
    if (await inbox.exists()) {
      if (await processing.exists()) {
        // Quedó algo de un corte anterior. Si el corte cae aquí, una línea se lee
        // dos veces, y procesarla dos veces no duplica.
        await processing.writeAsBytes(await inbox.readAsBytes(), mode: FileMode.append, flush: true);
        await inbox.delete();
      } else {
        await inbox.rename(processing.path);
      }
    }
    if (!await processing.exists()) return const [];
    final out = <CaptureEvent>[];
    // Por bytes: decodificar el archivo entero fallaría por una sola línea cortada
    // a mitad de un carácter, y bloquearía la bandeja para siempre.
    final bytes = await processing.readAsBytes();
    var start = 0;
    while (start < bytes.length) {
      var end = bytes.indexOf(0x0A, start);
      if (end == -1) end = bytes.length;
      final raw = bytes.sublist(start, end);
      start = end + 1;
      try {
        final line = utf8.decode(raw);
        if (line.trim().isEmpty) continue;
        out.add(CaptureEvent.fromJson((jsonDecode(line) as Map).cast<String, Object?>()));
      } catch (_) {
        // Sin el error: su mensaje puede citar la línea, con texto del banco.
        debugPrint('Línea ilegible en la bandeja de captura: se descarta.');
      }
    }
    return out;
  }

  /// Borra lo devuelto por [pending]: lo llegado después sigue en la bandeja.
  Future<void> commit() async {
    final processing = await _file(_processingName);
    if (processing != null && await processing.exists()) await processing.delete();
  }

  /// Devuelve lo pendiente y vacía la bandeja.
  Future<List<CaptureEvent>> drain() async {
    final events = await pending();
    await commit();
    return events;
  }

  /// Descarta todo sin leerlo.
  Future<void> clear() async {
    for (final name in const [_fileName, _processingName]) {
      final file = await _file(name);
      if (file != null && await file.exists()) await file.delete();
    }
  }
}
