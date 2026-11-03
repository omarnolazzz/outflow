import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/receipts/domain/receipt.dart';
import 'package:outflow/features/receipts/domain/receipt_heuristic.dart';

const taberna = '''
TABERNA LA ALEGRÍA
CALLE DE CAVA BAJA 24, 28005 MADRID
915 48 23 17 WWW.TABERNALAALEGRIA.ES
CIF: B-87654321
MESA 12 CAMARERO: LUCÍA
MARTES 8 SEPTIEMBRE 2026 21:47
TICKET Nº: 0342
1 ZUMO DE NARANJA 3,50 EUR
3 PATATAS BRAVAS 13,50 EUR
1 TORTILLA ESPAÑOLA 9,00 EUR
3 CROQUETAS JAMÓN 15,00 EUR
1 TIRAMISÚ 6,50 EUR
13 ART.
BASE IMPONIBLE 84,55
IVA 10% 8,45
TOTAL 93,00 EUR
¡GRACIAS POR SU VISITA!
''';

const bodega = '''
BODEGA SAN MARTIN S.A.C.
RUC 20512345678
AV. AREQUIPA 1234 - LIMA
BOLETA DE VENTA ELECTRONICA B001-00012345
FECHA: 08/10/2026 HORA: 18:22
2 GASEOSA 500ML 7.00
1 PAN DE MOLDE 8.50
1 LECHE GLORIA 4.90
3 GALLETAS 25.50
OP. GRAVADA 38.90
IGV 18% 7.00
SUBTOTAL 45.90
TOTAL S/ 45.90
EFECTIVO S/ 50.00
VUELTO S/ 4.10
''';

const plinConstancia = '''
Constancia de operación
Plin
S/ 35.00
Para: Marta Ejemplo Quispe
Fecha: 20/10/2026 18:45
Nro. de operación: 87654321
''';

void constanciaTests() {
  group('constancias de Plin y Yape', () {
    final now = DateTime(2026, 10, 22, 13);

    test('se leen importe, destinatario, fecha y número de operación', () {
      final r = parseReceiptHeuristic(plinConstancia, now: now, fallbackCurrency: 'PEN');
      expect(r.totalMinor, 3500);
      expect(r.currency, 'PEN');
      expect(r.merchant, 'Marta Ejemplo Quispe');
      expect(r.date, DateTime(2026, 10, 20));
      expect(r.operationId, '87654321');
    });

    test('el destinatario también se lee tras A, Destino o Nombre', () {
      for (final label in ['A:', 'Destino', 'Nombre:']) {
        final r = parseReceiptHeuristic(
          'Yape\nYapeaste S/ 12.50\n$label Luis Prueba\nN° de operación 5550001',
          now: now,
          fallbackCurrency: 'PEN',
        );
        expect(r.merchant, 'Luis Prueba', reason: label);
        expect(r.totalMinor, 1250, reason: label);
        expect(r.operationId, '5550001', reason: label);
      }
    });

    test('el texto suelto "Yape" o "Plin" en un ticket no lo vuelve constancia', () {
      for (final pay in ['Pago: Yape', 'Tarjeta/Plin']) {
        final r = parseReceiptHeuristic(
          'BODEGA SAN MARTIN\nFECHA: 08/10/2026\n2 GASEOSA 7.00\n$pay\nTOTAL S/ 45.90',
          now: now,
          fallbackCurrency: 'PEN',
        );
        expect(r.isConstancia, isFalse, reason: pay);
        expect(r.merchant, 'BODEGA SAN MARTIN', reason: pay);
        expect(r.operationId, isNull, reason: pay);
        expect(r.totalMinor, 4590, reason: pay);
      }
    });

    test('"Referencia: 123" sin palabra de transferencia no es constancia', () {
      final r = parseReceiptHeuristic('TIENDA X\nReferencia: 123\nTOTAL 10,00 EUR', now: now, fallbackCurrency: 'EUR');
      expect(r.isConstancia, isFalse);
      expect(r.operationId, isNull);
    });

    test('una constancia de Plin con forma real sí lo es', () {
      final r = parseReceiptHeuristic(plinConstancia, now: now, fallbackCurrency: 'PEN');
      expect(r.isConstancia, isTrue);
    });

    test('un ticket normal no tiene operationId aunque traiga un N°', () {
      for (final t in [taberna, bodega]) {
        final r = parseReceiptHeuristic(t, now: now, fallbackCurrency: 'PEN');
        expect(r.operationId, isNull);
      }
      final r = parseReceiptHeuristic('TIENDA X\nN° 12345\nTOTAL 10,00 EUR', now: now, fallbackCurrency: 'EUR');
      expect(r.operationId, isNull);
      expect(r.totalMinor, 1000);
    });
  });
}

void main() {
  reviewFixes();
  constanciaTests();
  final now = DateTime(2026, 10, 22);

  ReceiptData parse(String t) => parseReceiptHeuristic(t, now: now, fallbackCurrency: 'PEN');

  test('ticket español: total, fecha, comercio, moneda y productos', () {
    final r = parse(taberna);
    expect(r.totalMinor, 9300);
    expect(r.currency, 'EUR');
    expect(r.date, DateTime(2026, 9, 8));
    expect(r.merchant, 'TABERNA LA ALEGRÍA');
    expect(r.items.length, greaterThanOrEqualTo(3));
    expect(r.items.first.name, 'ZUMO DE NARANJA');
    expect(r.items.first.amountMinor, 350);
    expect(r.items[1].quantity, 3);
    expect(r.fromAi, isFalse);
  });

  test('boleta peruana: el total no es el subtotal, el efectivo ni el vuelto', () {
    final r = parse(bodega);
    expect(r.totalMinor, 4590);
    expect(r.currency, 'PEN');
    expect(r.date, DateTime(2026, 10, 8));
    expect(r.merchant, 'BODEGA SAN MARTIN S.A.C.');
    expect(r.items.map((i) => i.name), containsAll(['GASEOSA 500ML', 'PAN DE MOLDE', 'LECHE GLORIA']));
  });

  test('formatos de fecha', () {
    expect(parse('X\n8-9-26\nTOTAL 5.00').date, DateTime(2026, 9, 8));
    expect(parse('X\n2026-09-08\nTOTAL 5.00').date, DateTime(2026, 9, 8));
    expect(parse('X\nTOTAL 5.00').date, isNull);
  });

  test('una fecha futura se ignora', () {
    expect(parse('X\n08/12/2026\nTOTAL 5.00').date, isNull);
  });

  test('texto vacío: nada salvo la moneda principal', () {
    final r = parse('');
    expect(r.totalMinor, isNull);
    expect(r.merchant, isNull);
    expect(r.date, isNull);
    expect(r.items, isEmpty);
    expect(r.currency, 'PEN');
  });

  test('merge completa lo que falta con el respaldo', () {
    const ai = ReceiptData(merchant: 'Taberna', totalMinor: null, items: [], fromAi: true);
    final merged = ai.merge(parse(taberna));
    expect(merged.merchant, 'Taberna');
    expect(merged.totalMinor, 9300);
    expect(merged.items, isNotEmpty);
    expect(merged.fromAi, isTrue);
  });
}

const mercadona = '''
MERCADONA, S.A. A-46103834
C/ MAYOR 12 S/N 28013 MADRID
TELÉFONO: 910000000
12/10/2026 19:05 OP: 123456
FACTURA SIMPLIFICADA: 1234-567-890123
1 LECHE ENTERA 0,95
2 PAN DE BARRA 1,20
1 ACEITE OLIVA 8,95
TOTAL ARTICULOS 4
TOTAL (€) 23,45
TARJETA BANCARIA 23,45
IVA BASE IMPONIBLE (€) CUOTA (€)
4% 8,00 0,32
10% 13,74 1,37
TOTAL 21,74 1,69
''';

void reviewFixes() {
  final now = DateTime(2026, 10, 22);
  ReceiptData parse(String t, {String fallback = 'PEN'}) =>
      parseReceiptHeuristic(t, now: now, fallbackCurrency: fallback);

  test('el total es el del ticket, no el contador de artículos ni el desglose de IVA', () {
    expect(parse(mercadona, fallback: 'EUR').totalMinor, 2345);
  });

  test('"S/N" de una dirección o "PENDIENTE" no cambian la moneda', () {
    expect(parse('BAR PEPE\nC/ SOL S/N\nTOTAL 5,00', fallback: 'EUR').currency, 'EUR');
    expect(parse('TIENDA X\nPAGO PENDIENTE\nTOTAL 5.00', fallback: 'USD').currency, 'USD');
  });
}
