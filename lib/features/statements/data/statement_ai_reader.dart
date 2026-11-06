import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/gemini_config.dart';
import '../domain/parse_statement.dart';
import '../domain/statement.dart';

/// La IA no pudo leer el archivo. No lleva detalles: podrían contener el texto.
class StatementAiFailed implements Exception {
  const StatementAiFailed();
}

/// Lee un estado de cuenta con IA. Solo se usa tras activar el interruptor **Usar IA
/// para leer este archivo**, y solo recibe texto pasado por [maskNames] y [maskSensitive].
abstract interface class StatementAiReader {
  Future<ParsedStatement> read(String text, {required DateTime now, List<String?> names = const []});
}

/// Mismo cliente que `GeminiReceiptReader`. El texto del estado de cuenta nunca se
/// registra; ante cualquier fallo lanza [StatementAiFailed], sin inventar filas.
class GeminiStatementReader implements StatementAiReader {
  GeminiStatementReader(this._client, {required this.apiKey, required this.model, this.timeout = const Duration(seconds: 45)});

  final http.Client _client;
  final String apiKey;
  final String model;
  final Duration timeout;

  static const _schema = {
    'type': 'OBJECT',
    'properties': {
      'currency': {'type': 'STRING', 'description': 'Código ISO 4217'},
      'closingBalance': {'type': 'NUMBER', 'description': 'Saldo final, solo si el texto lo dice'},
      'rows': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'date': {'type': 'STRING', 'description': 'YYYY-MM-DD'},
            'description': {'type': 'STRING'},
            'amount': {'type': 'NUMBER', 'description': 'Negativo si sale dinero, positivo si entra'},
          },
        },
      },
    },
  };

  @override
  Future<ParsedStatement> read(String text, {required DateTime now, List<String?> names = const []}) async {
    try {
      final uri = Uri.https('generativelanguage.googleapis.com', '/v1beta/models/$model:generateContent', {'key': apiKey});
      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {
                'text': 'Extrae todos los movimientos de este estado de cuenta, uno por fila, también los que se '
                    'repiten. Las fechas están en formato día/mes/año. No incluyas totales ni saldos como '
                    'movimientos. Responde solo con el JSON.\n\n${maskSensitive(maskNames(text, names))}',
              },
            ],
          },
        ],
        'generationConfig': {'responseMimeType': 'application/json', 'responseSchema': _schema, 'temperature': 0},
      });
      final res = await _client.post(uri, headers: {'content-type': 'application/json'}, body: body).timeout(timeout);
      if (res.statusCode != 200) throw const StatementAiFailed();
      final reply = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
      final parts = (((reply['candidates'] as List).first as Map)['content'] as Map)['parts'] as List;
      final json = jsonDecode((parts.first as Map)['text'] as String) as Map<String, Object?>;
      return _fromJson(json, now);
    } on StatementAiFailed {
      rethrow;
    } catch (_) {
      throw const StatementAiFailed();
    }
  }

  static int? _minor(Object? v) => switch (v) {
        num n => (n * 100).round(),
        String s => parseSignedMinor(s),
        _ => null,
      };

  /// Una fila sin fecha válida, en el futuro o sin importe no se usa.
  static ParsedStatement _fromJson(Map<String, Object?> j, DateTime now) {
    final limit = now.add(const Duration(days: 1));
    final rows = <StatementRow>[];
    for (final r in j['rows'] is List ? j['rows']! as List : const []) {
      if (r is! Map) continue;
      final date = DateTime.tryParse(r['date'] is String ? r['date'] as String : '');
      final minor = _minor(r['amount']);
      final description = r['description'] is String ? (r['description'] as String).trim() : '';
      if (date == null || date.isAfter(limit) || minor == null || minor == 0) continue;
      rows.add(StatementRow(
        date: DateTime(date.year, date.month, date.day),
        description: description,
        amountMinor: minor.abs(),
        isCredit: minor > 0,
      ));
    }
    final currency = j['currency'] is String ? (j['currency'] as String).trim().toUpperCase() : null;
    return ParsedStatement(
      rows: rows,
      closingBalanceMinor: _minor(j['closingBalance']),
      currency: currency != null && RegExp(r'^[A-Z]{3}$').hasMatch(currency) ? currency : null,
    );
  }
}

/// Null si la build no trae clave de Gemini: entonces el interruptor no aparece.
final statementAiReaderProvider = Provider<StatementAiReader?>((ref) {
  if (!GeminiConfig.isConfigured) return null;
  final client = http.Client();
  ref.onDispose(client.close);
  return GeminiStatementReader(client, apiKey: GeminiConfig.apiKey, model: GeminiConfig.model);
});
