import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/charge_answer.dart';

/// Respuestas a la pregunta del cobro pulsadas con la app cerrada.
///
/// iOS ejecuta el botón en un proceso de fondo breve: escribir ahí la base de
/// datos cifrada (abierta quizá por la app suspendida) es arriesgado, así que
/// la respuesta se anota en un archivo de líneas JSON y la app la aplica al abrirse.
class ChargeAnswerInbox {
  const ChargeAnswerInbox();

  static const _fileName = 'charge_answers.jsonl';

  Future<File?> _file() async {
    if (kIsWeb) return null;
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> add(ChargeAnswer answer) async {
    final file = await _file();
    await file?.writeAsString('${jsonEncode(answer.toJson())}\n', mode: FileMode.append, flush: true);
  }

  /// Devuelve las respuestas guardadas y vacía la bandeja.
  Future<List<ChargeAnswer>> drain() async {
    final file = await _file();
    if (file == null || !await file.exists()) return const [];
    final lines = await file.readAsLines();
    await file.delete();
    final out = <ChargeAnswer>[];
    for (final line in lines.where((l) => l.trim().isNotEmpty)) {
      try {
        out.add(ChargeAnswer.fromJson((jsonDecode(line) as Map).cast<String, Object?>()));
      } catch (e) {
        debugPrint('Respuesta de notificación ilegible, se descarta: $e');
      }
    }
    return out;
  }
}

/// Botón de la notificación pulsado con la app en segundo plano o cerrada.
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationResponse(NotificationResponse response) async {
  final answer = ConfirmPayload.tryDecode(response.payload)?.answerFor(response.actionId);
  if (answer == null) return;
  DartPluginRegistrant.ensureInitialized();
  await const ChargeAnswerInbox().add(answer);
}
