import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/gemini_config.dart';
import '../../wallet/domain/apple_pay_link.dart' show parseAmountMinor;
import '../domain/receipt.dart';
import '../domain/receipt_heuristic.dart';

abstract interface class ReceiptReader {
  Future<ReceiptData> read(String text, {required DateTime now, required String fallbackCurrency});
}

/// Solo la lectura local (sin clave de Gemini o sin red).
class LocalReceiptReader implements ReceiptReader {
  const LocalReceiptReader();

  @override
  Future<ReceiptData> read(String text, {required DateTime now, required String fallbackCurrency}) async =>
      parseReceiptHeuristic(text, now: now, fallbackCurrency: fallbackCurrency);
}

/// Gemini interpreta el **texto** del ticket (nunca la foto) y devuelve JSON.
/// Cualquier fallo cae en la lectura local, que además completa lo que falte.
class GeminiReceiptReader implements ReceiptReader {
  GeminiReceiptReader(this._client, {required this.apiKey, required this.model, this.timeout = const Duration(seconds: 15)});

  final http.Client _client;
  final String apiKey;
  final String model;
  final Duration timeout;

  static const _schema = {
    'type': 'OBJECT',
    'properties': {
      'merchant': {'type': 'STRING'},
      'date': {'type': 'STRING', 'description': 'YYYY-MM-DD'},
      'total': {'type': 'NUMBER'},
      'currency': {'type': 'STRING', 'description': 'Código ISO 4217'},
      'items': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'name': {'type': 'STRING'},
            'quantity': {'type': 'INTEGER'},
            'amount': {'type': 'NUMBER', 'description': 'Importe total de la línea'},
          },
        },
      },
    },
  };

  @override
  Future<ReceiptData> read(String text, {required DateTime now, required String fallbackCurrency}) async {
    final local = parseReceiptHeuristic(text, now: now, fallbackCurrency: fallbackCurrency);
    try {
      final uri = Uri.https('generativelanguage.googleapis.com', '/v1beta/models/$model:generateContent', {'key': apiKey});
      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {
                'text': 'Extrae los datos de este ticket de compra. Usa el total final pagado '
                    '(no el subtotal ni el vuelto). Responde solo con el JSON.\n\n$text',
              },
            ],
          },
        ],
        'generationConfig': {'responseMimeType': 'application/json', 'responseSchema': _schema, 'temperature': 0},
      });
      final res = await _client
          .post(uri, headers: {'content-type': 'application/json'}, body: body)
          .timeout(timeout);
      if (res.statusCode != 200) return local;
      final reply = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, Object?>;
      final part = (((reply['candidates'] as List).first as Map)['content'] as Map)['parts'] as List;
      final json = jsonDecode((part.first as Map)['text'] as String) as Map<String, Object?>;
      return _fromJson(json, now).merge(local);
    } catch (e) {
      debugPrint('Gemini no pudo leer el ticket: $e');
      return local;
    }
  }

  static int? _minor(Object? v) => switch (v) {
        num n => (n * 100).round(),
        String s => parseAmountMinor(s),
        _ => null,
      };

  static ReceiptData _fromJson(Map<String, Object?> j, DateTime now) {
    final date = DateTime.tryParse(j['date'] as String? ?? '');
    final today = DateTime(now.year, now.month, now.day);
    return ReceiptData(
      merchant: (j['merchant'] as String?)?.trim(),
      date: date == null || date.isAfter(today) ? null : DateTime(date.year, date.month, date.day),
      totalMinor: _minor(j['total']),
      currency: (j['currency'] as String?)?.toUpperCase(),
      items: [
        for (final i in (j['items'] as List?) ?? const [])
          if (i is Map && i['name'] is String && _minor(i['amount']) != null)
            ReceiptItem(
              name: (i['name'] as String).trim(),
              quantity: (i['quantity'] as num?)?.toInt() ?? 1,
              amountMinor: _minor(i['amount'])!,
            ),
      ],
      fromAi: true,
    );
  }
}

/// Gemini si la build trae clave; si no, lectura local.
final receiptReaderProvider = Provider<ReceiptReader>((ref) {
  if (!GeminiConfig.isConfigured) return const LocalReceiptReader();
  final client = http.Client();
  ref.onDispose(client.close);
  return GeminiReceiptReader(client, apiKey: GeminiConfig.apiKey, model: GeminiConfig.model);
});
