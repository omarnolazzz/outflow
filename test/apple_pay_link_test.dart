import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/wallet/domain/apple_pay_link.dart';
import 'package:outflow/features/wallet/domain/movement.dart';

void main() {
  final now = DateTime(2026, 10, 22, 13, 5);

  MovementDraft? parse(String importe, {String comercio = 'Starbucks', String? tarjeta}) => parseApplePayLink(
        Uri(
          scheme: 'outflow',
          host: 'gasto',
          queryParameters: {'importe': importe, 'comercio': comercio, 'tarjeta': ?tarjeta},
        ),
        fallbackCurrency: 'PEN',
        now: now,
      );

  test('formatos de importe habituales', () {
    expect(parse('S/ 12.50')!.amountMinor, 1250);
    expect(parse('S/ 12.50')!.currency, 'PEN');
    expect(parse('12,50')!.amountMinor, 1250);
    expect(parse('1.234,56')!.amountMinor, 123456);
    expect(parse('1,234.56')!.amountMinor, 123456);
    expect(parse('12')!.amountMinor, 1200);
    expect(parse('PEN 12.50')!.amountMinor, 1250);
  });

  test('otra moneda reconocible se respeta', () {
    expect(parse('USD 9.99')!.currency, 'USD');
    expect(parse('US\$ 9.99')!.amountMinor, 999);
    expect(parse('US\$ 9.99')!.currency, 'USD');
    expect(parse('€ 3,40')!.currency, 'EUR');
  });

  test('sin moneda se usa la principal', () {
    expect(parse('12.50')!.currency, 'PEN');
  });

  test('importe vacío o ilegible deja la hoja sin importe', () {
    expect(parse('')!.amountMinor, isNull);
    expect(parse('abc')!.amountMinor, isNull);
  });

  test('comercio recortado, tarjeta en la nota, origen Apple Pay y fecha actual', () {
    final d = parse('5', comercio: '  Starbucks  ', tarjeta: 'Visa')!;
    expect(d.title, 'Starbucks');
    expect(d.note, 'Tarjeta: Visa');
    expect(d.origin, MovementOrigin.applePay);
    expect(d.date, now);
    expect(parse('5')!.note, '');
  });

  test('otro enlace no es un pago', () {
    expect(parseApplePayLink(Uri.parse('outflow://otra?importe=5'), fallbackCurrency: 'PEN', now: now), isNull);
    expect(parseApplePayLink(Uri.parse('https://gasto?importe=5'), fallbackCurrency: 'PEN', now: now), isNull);
  });
}
