import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:outflow/features/statements/data/statement_ai_reader.dart';
import 'package:outflow/features/statements/domain/parse_statement.dart';

void main() {
  group('maskSensitive', () {
    test('oculta números largos, con o sin separadores', () {
      expect(maskSensitive('CCI 19112345678901 fin'), 'CCI ************** fin');
      expect(maskSensitive('Tarjeta 4111 1111 1111 1111.'), isNot(contains('1111')));
      expect(maskSensitive('Cuenta 191-1234-5678-90'), isNot(contains('1234')));
      expect(maskSensitive('12345678'), '********');
    });

    test('no toca importes ni fechas', () {
      for (final keep in [
        '1,250.50',
        '1.250,50',
        '12345678.90',
        '-45.58',
        'S/ 3000.00',
        '08/09/2026',
        '8/9/2026',
        '08-09-2026',
        '2026-09-08',
        '1,234,567.00',
        '1234567',
      ]) {
        expect(maskSensitive('a $keep b'), 'a $keep b', reason: keep);
      }
    });

    test('un número largo junto a importes o fechas no los arrastra', () {
      expect(maskSensitive('12345678 100.00'), '******** 100.00');
      expect(maskSensitive('08/09/2026 12345678 1,250.50'), '08/09/2026 ******** 1,250.50');
      expect(maskSensitive('12345678 08/09/2026'), '******** 08/09/2026');
      expect(maskSensitive('1,250.50 3,000.00'), '1,250.50 3,000.00');
    });
  });

  group('GeminiStatementReader', () {
    http.Response reply(Map<String, Object?> json) => http.Response.bytes(
          utf8.encode(jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': jsonEncode(json)},
                  ],
                },
              },
            ],
          })),
          200,
        );

    test('solo envía el texto enmascarado y devuelve filas válidas', () async {
      String? sent;
      final reader = GeminiStatementReader(
        MockClient((req) async {
          sent = req.body;
          return reply({
            'currency': 'PEN',
            'closingBalance': 1054.42,
            'rows': [
              {'date': '2026-10-01', 'description': 'Compra', 'amount': -45.58},
              {'date': '2026-10-02', 'description': 'Sueldo', 'amount': 3000},
              // Inválidas: sin importe, sin fecha y en el futuro.
              {'date': '2026-10-02', 'description': 'Sin importe'},
              {'description': 'Sin fecha', 'amount': 1},
              {'date': '2030-01-01', 'description': 'Futuro', 'amount': 1},
            ],
          });
        }),
        apiKey: 'k',
        model: 'm',
      );
      final parsed = await reader.read('Cuenta 19112345678901\n01/10 Compra -45.58', now: DateTime(2026, 11, 3));

      expect(sent, isNot(contains('19112345678901')));
      expect(sent, contains('-45.58'));
      expect(parsed.rows, hasLength(2));
      expect(parsed.rows[0].date, DateTime(2026, 10, 1));
      expect(parsed.rows[0].amountMinor, 4558);
      expect(parsed.rows[0].isCredit, isFalse);
      expect(parsed.rows[1].amountMinor, 300000);
      expect(parsed.rows[1].isCredit, isTrue);
      expect(parsed.closingBalanceMinor, 105442);
      expect(parsed.currency, 'PEN');
    });

    test('un fallo de la IA se informa sin inventar filas', () async {
      final reader = GeminiStatementReader(MockClient((_) async => http.Response('no', 500)), apiKey: 'k', model: 'm');
      await expectLater(reader.read('texto', now: DateTime(2026, 11, 3)), throwsA(isA<StatementAiFailed>()));
    });
  });
}
