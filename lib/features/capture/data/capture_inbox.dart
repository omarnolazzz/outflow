import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/process_captures.dart';

export '../domain/process_captures.dart' show CaptureEvent;

final captureInboxProvider = Provider<CaptureInbox>((ref) => CaptureInbox());

/// Textos bancarios pendientes de leer, de cualquier fuente: un archivo de líneas
/// JSON que escriben también los procesos nativos. El texto no se escribe en los
/// registros ni sale del teléfono, y el archivo se borra al terminar.
///
/// Para que un corte no pierda nada se procesa en dos pasos: [pending] aparta lo
/// que hay (lo que llegue luego sigue en la bandeja) y [commit], una vez guardados
/// los movimientos, lo borra. Tras un corte, [pending] vuelve a devolverlo.
class CaptureInbox {
  CaptureInbox({this.directory});

  /// Carpeta de la bandeja (por defecto, los documentos de la app).
  final Future<Directory> Function()? directory;

  static const _fileName = 'capture_inbox.jsonl';
  static const _processingName = 'capture_inbox.processing';
  static const _mergePrefix = 'capture_inbox.merge.';

  /// Bytes de `.processing` que leyó [pending], para que [commit] no borre lo que llegó después.
  int? _readLength;

  Future<File?> _file(String name) async {
    if (kIsWeb) return null;
    final dir = await (directory ?? getApplicationDocumentsDirectory)();
    return File('${dir.path}/$name');
  }

  Future<void> add(CaptureEvent event) async {
    final file = await _file(_fileName);
    await file?.writeAsString('${jsonEncode(event.toJson())}\n', mode: FileMode.append, flush: true);
  }

  /// Restos de una unión interrumpida: `capture_inbox.merge.<microsegundos>`.
  Future<List<File>> _merges() async {
    if (kIsWeb) return const [];
    final dir = await (directory ?? getApplicationDocumentsDirectory)();
    if (!await dir.exists()) return const [];
    final out = <File>[];
    await for (final e in dir.list()) {
      if (e is File && e.uri.pathSegments.last.startsWith(_mergePrefix)) out.add(e);
    }
    return out..sort((x, y) => x.path.compareTo(y.path));
  }

  /// Añade [source] a [target] y lo borra. Si el servicio escribió en [source] mientras
  /// tanto (lo tenía abierto antes de renombrarlo), se copia también lo último.
  Future<void> _absorb(File source, File target) async {
    var copied = 0;
    while (true) {
      final bytes = await source.readAsBytes();
      if (bytes.length <= copied) break;
      await target.writeAsBytes(bytes.sublist(copied), mode: FileMode.append, flush: true);
      copied = bytes.length;
      if (await source.length() == copied) break;
    }
    await source.delete();
  }

  /// Lo pendiente, sin borrarlo. Una línea ilegible se salta sin perder las demás.
  Future<List<CaptureEvent>> pending() async {
    final inbox = await _file(_fileName);
    final processing = await _file(_processingName);
    if (inbox == null || processing == null) return const [];
    // Restos de un corte durante una unión: se recogen primero.
    for (final leftover in await _merges()) {
      await _absorb(leftover, processing);
    }
    if (await inbox.exists()) {
      if (await processing.exists()) {
        // Quedó algo de un corte anterior. Se aparta la bandeja con un nombre único
        // (rename atómico) antes de leerla: lo que el servicio añada después va a
        // una bandeja nueva, no a un archivo que vamos a borrar.
        final merge = File('${inbox.parent.path}/$_mergePrefix${DateTime.now().microsecondsSinceEpoch}');
        await inbox.rename(merge.path);
        await _absorb(merge, processing);
      } else {
        await inbox.rename(processing.path);
      }
    }
    if (!await processing.exists()) return const [];
    final out = <CaptureEvent>[];
    // Por bytes: decodificar el archivo entero fallaría por una sola línea cortada
    // a mitad de un carácter, y bloquearía la bandeja para siempre.
    final bytes = await processing.readAsBytes();
    _readLength = bytes.length;
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

  /// Borra lo devuelto por [pending]: lo llegado después sigue en la bandeja. Si
  /// `.processing` creció tras leerse (el servicio tenía el archivo abierto durante el
  /// rename), lo de más se aparta como resto de unión y se procesa la próxima vez.
  Future<void> commit() async {
    final processing = await _file(_processingName);
    final read = _readLength;
    _readLength = null;
    if (processing == null || !await processing.exists()) return;
    if (read != null) {
      final bytes = await processing.readAsBytes();
      if (bytes.length > read) {
        final rest = File('${processing.parent.path}/$_mergePrefix${DateTime.now().microsecondsSinceEpoch}');
        await rest.writeAsBytes(bytes.sublist(read), flush: true);
      }
    }
    await processing.delete();
  }

  /// Devuelve lo pendiente y vacía la bandeja.
  Future<List<CaptureEvent>> drain() async {
    final events = await pending();
    await commit();
    return events;
  }

  /// Descarta todo sin leerlo.
  Future<void> clear() async {
    _readLength = null;
    for (final name in const [_fileName, _processingName]) {
      final file = await _file(name);
      if (file != null && await file.exists()) await file.delete();
    }
    for (final leftover in await _merges()) {
      if (await leftover.exists()) await leftover.delete();
    }
  }
}
