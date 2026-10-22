import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:outflow/features/receipts/data/gemini_receipt_reader.dart';

const ticket = 'BODEGA SAN MARTIN\nFECHA: 08/10/2026\n2 GASEOSA 7.00\nTOTAL S/ 45.90';

String geminiReply(Map<String, Object?> json) => jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': jsonEncode(json)},
            ],
          },
        },
      ],
    });

void main() {
  final now = DateTime(2026, 10, 22);

  test('respuesta válida: datos de la IA; la petición lleva el texto y ninguna imagen', () async {
    late http.Request sent;
    final client = MockClient((req) async {
      sent = req;
      return http.Response(
        geminiReply({
          'merchant': 'Bodega San Martín',
          'date': '2026-10-08',
          'total': 45.9,
          'currency': 'PEN',
          'items': [
            {'name': 'Gaseosa', 'quantity': 2, 'amount': 7},
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final r = await GeminiReceiptReader(client, apiKey: 'k', model: 'm').read(ticket, now: now, fallbackCurrency: 'PEN');
    expect(r.fromAi, isTrue);
    expect(r.merchant, 'Bodega San Martín');
    expect(r.totalMinor, 4590);
    expect(r.date, DateTime(2026, 10, 8));
    expect(r.items.single.amountMinor, 700);
    expect(r.items.single.quantity, 2);
    expect(sent.url.path, contains('/models/m:generateContent'));
    expect(sent.url.queryParameters['key'], 'k');
    expect(sent.body, contains('TOTAL S/ 45.90'));
    expect(sent.body, isNot(contains('inline_data')));
    expect(sent.body, isNot(contains('inlineData')));
  });

  test('importes como texto con coma se entienden', () async {
    final client = MockClient((_) async => http.Response(geminiReply({'total': '45,90', 'items': []}), 200));
    final r = await GeminiReceiptReader(client, apiKey: 'k', model: 'm').read(ticket, now: now, fallbackCurrency: 'PEN');
    expect(r.totalMinor, 4590);
    expect(r.merchant, 'BODEGA SAN MARTIN', reason: 'lo que falta lo completa la heurística');
  });

  test('error 500, JSON roto o tiempo agotado → lectura local', () async {
    for (final client in [
      MockClient((_) async => http.Response('boom', 500)),
      MockClient((_) async => http.Response(geminiReply({'total': 'no'}).replaceAll('{', ''), 200)),
      MockClient((_) => Completer<http.Response>().future),
    ]) {
      final r = await GeminiReceiptReader(client, apiKey: 'k', model: 'm', timeout: const Duration(milliseconds: 50))
          .read(ticket, now: now, fallbackCurrency: 'PEN');
      expect(r.fromAi, isFalse);
      expect(r.totalMinor, 4590);
    }
  });

  test('sin clave solo se usa la lectura local', () async {
    final r = await const LocalReceiptReader().read(ticket, now: now, fallbackCurrency: 'PEN');
    expect(r.fromAi, isFalse);
    expect(r.totalMinor, 4590);
  });
}
