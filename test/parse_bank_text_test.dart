import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/capture/domain/parse_bank_text.dart';
import 'package:outflow/features/wallet/domain/apple_pay_link.dart';

/// Correo inventado con la forma real de Lemon/Dale: ningún dato es de verdad.
const kLemonMail = '''
Enviaste S/ 4 💸
Lucía Prueba, ¡realizaste un envío exitoso de S/ 4.0000!:
Nombre: Ana Torres Vega
N° de teléfono: N/A
CCI: 00219300000000000011
Entidad: BCP
ID de la operación: 3f2a9c10-7b1d-4e55-9a01-0c1d2e3f4a5b
ID externo: 1234567890123456789012345678
''';

void main() {
  final now = DateTime(2026, 11, 3, 12);

  ParsedBankText? parse(String text, {String fallback = 'PEN'}) =>
      parseBankText(text, fallbackCurrency: fallback, now: now);

  group('parseAmountMinor', () {
    test('cuatro decimales no son miles', () {
      expect(parseAmountMinor('S/ 4.0000'), 400);
      expect(parseAmountMinor('4,0000'), 400);
      expect(parseAmountMinor('1,250.5000'), 125050);
    });

    test('los formatos de siempre no cambian', () {
      expect(parseAmountMinor('S/ 1,250.50'), 125050);
      expect(parseAmountMinor('1.250,50'), 125050);
      expect(parseAmountMinor('PEN 45'), 4500);
      expect(parseAmountMinor('1.234'), 123400, reason: 'tres cifras tras un único separador son miles');
      expect(parseAmountMinor('1.234.567'), 123456700);
      expect(parseAmountMinor('12,5'), 1250);
    });
  });

  group('importe', () {
    test('formatos peruanos', () {
      expect(parse('Pagaste S/ 1,250.50 en Tambo')!.amountMinor, 125050);
      expect(parse('Pagaste S/ 1.250,50 en Tambo')!.amountMinor, 125050);
      expect(parse('Pagaste PEN 45 en Tambo')!.amountMinor, 4500);
      expect(parse('Pagaste S/. 12.50 en Tambo')!.amountMinor, 1250);
      expect(parse('Constancia de operación\nMonto: 1.250,50')!.amountMinor, 125050);
    });

    test('un importe solo, sin nada que lo confirme, no es un movimiento', () {
      for (final t in const ['S/ 1,250.50', '1.250,50', 'PEN 45', '10.50', 'Monto: S/ 45.00']) {
        expect(parse(t), isNull, reason: t);
      }
    });

    test('lista permitida: sin señal de operación, null', () {
      for (final t in const [
        'Paga con Yape y recibe S/ 10',
        'Haz tu primera compra y llévate S/ 20',
        'Con Yape tienes S/ 5 de regalo',
        'Tu primera transferencia de S/ 50 es gratis',
        'Compra S/ 20 y participa',
        'Tienes un pago pendiente de S/ 250.00',
        'Hubo un problema con tu pago de S/ 25.00',
        'Tu clave es 482913 para la compra de S/ 50.00 en Tienda',
        'Token 482913 para tu compra de S/ 50.00',
        'Tu estado de cuenta: total S/ 500.00',
        'Total a pagar S/ 500.00',
        'Por tu compra de S/ 50.00 en Wong llévate un premio',
        'Si pagaste S/ 50.00 con otra tarjeta, avísanos',
        'Operación rechazada\nMonto: S/ 50.00',
        'Constancia de operación\nMonto: S/ 50.00\nEstado: Rechazado',
      ]) {
        expect(parse(t), isNull, reason: t);
      }
    });

    test('un pie de correo no anula una operación real', () {
      final constancia = parse('Constancia de transferencia\nMonto: S/ 150.00\nDestino: Ana\nRecuerda que nunca te pediremos tus claves.')!;
      expect(constancia.amountMinor, 15000);
      expect(constancia.direction, CaptureDirection.out);
      final consumo = parse('Consumo de S/ 45.00 en Tambo\nConoce nuestras promociones en la app.')!;
      expect(consumo.amountMinor, 4500);
      expect(consumo.direction, CaptureDirection.out);
    });

    test('consumo o cargo justo antes del importe bastan, sin comercio', () {
      for (final (text, minor) in const [
        ('Consumo S/ 25.00', 2500),
        ('Consumo de S/ 25.00', 2500),
        ('Consumo por S/ 25.00', 2500),
        ('Cargo de S/ 12.00', 1200),
        ('Cargo S/ 12.00', 1200),
      ]) {
        final p = parse(text)!;
        expect(p.amountMinor, minor, reason: text);
        expect(p.direction, CaptureDirection.out, reason: text);
      }
    });

    test('compra sigue siendo estricta; consumo o cargo lejos del importe no bastan', () {
      for (final t in const [
        'Compra S/ 20 y participa',
        'Compra de S/ 20',
        'Tu consumo mensual promedio es S/ 25.00',
        'Cargo de S/ 12.00 por mantenimiento',
        'Tu próximo cargo S/ 12.00',
      ]) {
        expect(parse(t), isNull, reason: t);
      }
    });

    test('sin verbo en pasado, una clave con su número bloquea todo el texto', () {
      for (final t in const [
        'Tu clave es 482913\nCompra de S/ 50 en Tienda',
        'Token 482913\nConsumo de S/ 50.00 en Tienda',
        'OTP: 4829\nConsumo de S/ 50.00 en Tienda',
        'Código: 48291300\nCargo de S/ 50.00',
        'Tu código de verificación es 482913\nCompra de S/ 50 en Tienda',
      ]) {
        expect(parse(t), isNull, reason: t);
      }
    });

    test('la palabra sola, o un identificador de la operación, no bloquean', () {
      for (final t in const [
        'Consumo de S/ 45.00 en Tambo\nNo compartas tu clave con nadie',
        'Consumo de S/ 45.00 en Tambo\nCódigo de operación: 123456',
        'Consumo de S/ 45.00 en Tambo\nCódigo de autorización: 123456',
      ]) {
        expect(parse(t)!.amountMinor, 4500, reason: t);
      }
      expect(parse('Consumo de S/ 45.00 en Tambo\nCódigo de operación: 123456')!.operationId, '123456');
    });

    test('con un verbo en pasado, una clave en otra línea no anula el pago', () {
      expect(parse('Pagaste S/ 25.00 en Tambo\nTu clave es 482913')!.amountMinor, 2500);
    });

    test('la moneda sale del texto y si no, de la principal', () {
      expect(parse('Pagaste USD 9.99 en Amazon')!.currency, 'USD');
      expect(parse('Pagaste S/ 9.99 en Tambo', fallback: 'USD')!.currency, 'PEN');
      expect(parse('Operación exitosa. Monto: 45.00', fallback: 'MXN')!.currency, 'MXN');
      expect(parse(r'Pagaste $ 12.50 en Oxxo', fallback: 'MXN')!.currency, 'MXN');
      expect(parse(r'Pagaste $ 12.50 en Amazon')!.currency, 'USD');
      expect(parse('Recibiste 20 soles de Ana')!.currency, 'PEN');
      expect(parse('Recibiste 20 soles de Ana')!.amountMinor, 2000);
    });

    test('gana el importe de la operación, no el saldo', () {
      expect(parse('Pagaste S/ 25.00 en Tambo. Tu saldo disponible es S/ 900.00')!.amountMinor, 2500);
      expect(parse('Pagaste S/ 25.00… saldo disponible S/ 900.00')!.amountMinor, 2500);
      expect(parse('Pagaste S/ 25.00 saldo disponible S/ 900.00')!.amountMinor, 2500);
      expect(parse('Saldo disponible S/ 900.00. Pagaste S/ 25.00 en Tambo')!.amountMinor, 2500);
      expect(parse('Tienes S/ 900.00 disponibles. Compra de S/ 25.00 en Tambo')!.amountMinor, 2500);
    });

    test('gana el importe de la operación, no la comisión', () {
      expect(parse('Comisión S/ 1.00… Transferiste S/ 500.00')!.amountMinor, 50000);
      expect(parse('Transferiste S/ 500.00. ITF S/ 0.25')!.amountMinor, 50000);
      expect(parse('Transferiste S/ 500.00 con S/ 1.00 de comisión')!.amountMinor, 50000);
      expect(parse('Constancia de operación\nMonto: S/ 500.00 Comisión: S/ 5.00 Total: S/ 505.00')!.amountMinor, 50000);
      expect(parse('Constancia de operación\nComisión: S/ 5.00 Total: S/ 505.00 Monto: S/ 500.00')!.amountMinor, 50000);
    });

    test('solo saldo, comisión o ITF no es un movimiento', () {
      expect(parse('Tu saldo disponible es S/ 900.00'), isNull);
      expect(parse('Comisión de mantenimiento S/ 5.00'), isNull);
      expect(parse('ITF S/ 0.25'), isNull);
      expect(parse('Tienes S/ 900.00 disponibles'), isNull);
      expect(parse('S/ 900.00 de saldo'), isNull);
    });

    test('sin importe, null', () {
      expect(parse('Tu cuenta se abrió en un dispositivo nuevo'), isNull);
      expect(parse(''), isNull);
      expect(parse('Pagaste en Tambo'), isNull);
      expect(parse('Pagaste S/ 0.00 en Tambo'), isNull);
    });

    test('un número suelto no es un importe', () {
      expect(parse('Tu código es 123456'), isNull);
      expect(parse('Recibiste 3 mensajes nuevos'), isNull);
      expect(parse('CCI: 00219300000000000011'), isNull);
      expect(parse('ID externo: 1234567890123456789012345678'), isNull);
      expect(parse('Llámanos al 987654321'), isNull);
      expect(parse('Tu pago del 03/11/2026'), isNull);
      expect(parse('1234'), isNull);
    });

    test('teléfonos, fechas e identificadores no se confunden con el importe', () {
      expect(parse('Enviaste a 987654321 S/ 20.00')!.amountMinor, 2000);
      expect(parse('Operación 123456: pagaste S/ 20.00')!.amountMinor, 2000);
      expect(parse('03/11/2026 14:30 Pagaste S/ 20.00')!.amountMinor, 2000);
      expect(parse('Pagaste S/ 20.00 con tu tarjeta ****1234')!.amountMinor, 2000);
      expect(parse('Monto de la operación: 500.00')!.amountMinor, 50000);
    });

    test('lo que no ocurrió no se apunta', () {
      expect(parse('Tu compra de S/ 50.00 fue rechazada'), isNull);
      expect(parse('No pudimos procesar tu pago de S/ 50.00'), isNull);
      expect(parse('Tu clave dinámica para autorizar la compra de S/ 50.00 es 123456'), isNull);
      expect(parse('Tu pago de S/ 300.00 vence el 20/11'), isNull);
      expect(parse('Aprovecha: compras desde S/ 100.00 con descuento'), isNull);
      expect(parse('Gana S/ 50 con tu tarjeta'), isNull);
      expect(parse('Préstamo de S/ 5,000 para ti'), isNull);
    });

    test('un pie de correo no anula un pago hecho', () {
      expect(parse('Pagaste S/ 25.00 en Tambo.\nSi un pago fue rechazado, llámanos. Aprovecha nuestras ofertas.')!.amountMinor, 2500);
    });

    test('dos importes sin nada que los distinga: no se adivina', () {
      expect(parse('S/ 10.00 y S/ 20.00 recibidos'), isNull);
    });
  });

  group('sentido', () {
    test('verbos de salida', () {
      for (final t in const [
        'Pagaste S/ 25.00',
        'Enviaste S/ 25.00',
        'Transferiste S/ 25.00',
        'Compra de S/ 25.00 en Tambo',
        'Consumo por S/ 25.00 en Tambo',
        'Tu pago de S/ 25.00 fue recibido',
        'Hemos recibido tu pago de S/ 100.00',
        'Tu solicitud fue recibida. Compra de S/ 20.00 en Tienda',
        'Se realizó un consumo de S/ 25.00',
        'Si recibiste esto por error, llámanos.\nPagaste S/ 25.00 en Tambo',
        'Pagaste S/ 25.00 en Tambo\nSi recibiste este correo por error, llámanos.',
        'Constancia de transferencia\nMonto: S/ 25.00\nSi recibiste esto por error, llámanos.',
      ]) {
        expect(parse(t)!.direction, CaptureDirection.out, reason: t);
      }
    });

    test('verbos de entrada', () {
      for (final t in const [
        'Recibiste S/ 25.00',
        'Ana te envió S/ 25.00',
        'Te yapearon S/ 25.00',
        'Abono de S/ 25.00 en tu cuenta',
        'Depósito de S/ 25.00 en tu cuenta',
        'Se realizó un abono de S/ 100.00 a tu cuenta',
        'Se realizó un depósito de S/ 100.00',
        'Reembolso de tu compra S/ 30.00',
        'Depositaste S/ 100.00 en tu cuenta',
        'Transferencia recibida: S/ 50.00 de Ana',
        'Constancia de depósito\nMonto: S/ 25.00',
        'Recibiste un Yape\nMonto: S/ 25.00',
        'Recibiste un pago de S/ 25.00',
        'S/ 25.00 recibidos',
      ]) {
        expect(parse(t)!.direction, CaptureDirection.inbound, reason: t);
      }
    });
  });

  group('datos de la operación', () {
    test('comercio o persona', () {
      expect(parse('Pagaste S/ 25.00 en Tambo. Saldo S/ 9.00')!.counterparty, 'Tambo');
      expect(parse('Consumo de S/ 45 en PLAZA VEA con tu tarjeta ****1234 el 02/11/2026')!.counterparty, 'PLAZA VEA');
      expect(parse('Enviaste S/ 20.00 a Ana Pérez')!.counterparty, 'Ana Pérez');
      expect(parse('Recibiste S/ 50.00 de Ana Pérez en tu cuenta')!.counterparty, 'Ana Pérez');
      expect(parse('Yape: Ana Pérez te envió S/ 20.00')!.counterparty, 'Ana Pérez');
      expect(parse('Comercio: Tambo\nMonto: S/ 20.00')!.counterparty, 'Tambo');
      expect(parse('Pagaste S/ 25.00')!.counterparty, isNull);
      expect(parse('Pagaste S/ 25.00 en tu cuenta')!.counterparty, isNull);
    });

    test('número de operación, nunca una palabra', () {
      expect(parse('Pagaste S/ 25.00. N° de operación: 12345678')!.operationId, '12345678');
      expect(parse('Pagaste S/ 25.00. Referencia: AB12CD')!.operationId, 'AB12CD');
      expect(parse('Operación exitosa. Pagaste S/ 25.00')!.operationId, isNull);
      expect(parse('Pagaste S/ 25.00. Nro. de operación: 556677')!.operationId, '556677');
      expect(parse('Pagaste S/ 25.00. Código de operación: 8899')!.operationId, '8899');
      expect(parse('Pagaste S/ 25.00. Operación: 4433')!.operationId, '4433');
    });

    test('un número suelto de tarjeta, cuenta, comercio o cliente no es número de operación', () {
      for (final t in const [
        'Compraste S/ 25.00 en Tambo con tarjeta N° 1234',
        'Pagaste S/ 25.00 con cuenta Nro 5678',
        'Pagaste S/ 25.00. Cta N° 5678',
        'Pagaste S/ 25.00. Comercio N° 44556',
        'Pagaste S/ 25.00. Cliente Nro 998877',
        'Pagaste S/ 25.00. N° 1234',
        'Pagaste S/ 25.00. Código 1234',
        'Pagaste S/ 25.00. Comercio referencia 1234',
      ]) {
        expect(parse(t)!.operationId, isNull, reason: t);
      }
    });

    test('la cuenta usada, no la de destino ni el CCI', () {
      expect(parse('Pagaste S/ 25.00 con tu tarjeta ****1234')!.accountDigits, '1234');
      expect(parse('Pagaste S/ 25.00 con tarjeta terminada en 987')!.accountDigits, '987');
      final t = parse('Transferiste S/ 25.00 desde tu cuenta ****1234 a la cuenta ****5678')!;
      expect(t.accountDigits, '1234');
      expect(t.toAccountDigits, '5678');
      expect(parse('Transferiste S/ 25.00 a la cuenta ****5678')!.accountDigits, isNull);
      expect(parse('Recibiste S/ 25.00 en tu cuenta ****1234')!.accountDigits, '1234');
      expect(parse('Enviaste S/ 25.00. CCI: 00219300000000000011')!.accountDigits, isNull);
    });

    test('fecha del texto, solo si es válida y no es futura', () {
      expect(parse('Pagaste S/ 25.00 el 02/11/2026')!.date, DateTime(2026, 11, 2));
      expect(parse('Pagaste S/ 25.00. Fecha: 02/11/2026 14:30')!.date, DateTime(2026, 11, 2, 14, 30));
      expect(parse('Pagaste S/ 25.00 el 2 de noviembre')!.date, DateTime(2026, 11, 2));
      expect(parse('Pagaste S/ 25.00 el 2026-11-02')!.date, DateTime(2026, 11, 2));
      expect(parse('Pagaste S/ 25.00 el 31/02/2026')!.date, isNull);
      expect(parse('Pagaste S/ 25.00 el 20/12/2026')!.date, isNull);
      expect(parse('Pagaste S/ 25.00')!.date, isNull);
    });

    test('una fecha de otra frase y sin etiqueta no es la de la operación', () {
      expect(parse('Pagaste S/ 25.00 en Tambo\nTérminos actualizados el 01/02/2026')!.date, isNull);
      expect(parse('Pagaste S/ 25.00 en Tambo\nFecha: 02/11/2026')!.date, DateTime(2026, 11, 2));
    });

    test('es transferencia si el texto lo dice; una compra, no', () {
      expect(parse('Transferiste S/ 25.00 a Ana')!.isTransfer, isTrue);
      expect(parse('Plin: enviaste S/ 25.00 a Ana')!.isTransfer, isTrue);
      expect(parse('Pagaste S/ 25.00 en Tambo')!.isTransfer, isFalse);
      expect(parse('Compra de S/ 25.00 en Tambo')!.isTransfer, isFalse);
    });
  });

  group('regla de Lemon/Dale', () {
    test('lee el correo completo', () {
      final p = parse(kLemonMail)!;
      expect(p.amountMinor, 400, reason: 'S/ 4.0000 son S/ 4.00, nunca 4000');
      expect(p.currency, 'PEN');
      expect(p.direction, CaptureDirection.out);
      expect(p.counterparty, 'Ana Torres Vega');
      expect(p.operationId, '3f2a9c10-7b1d-4e55-9a01-0c1d2e3f4a5b');
      expect(p.isTransfer, isTrue);
      expect(p.date, isNull, reason: 'el cuerpo no trae fecha: se usa la de recepción');
      expect(p.accountDigits, isNull);
    });

    test('también con todo en una línea', () {
      final p = parse(kLemonMail.replaceAll('\n', ' '))!;
      expect(p.amountMinor, 400);
      expect(p.counterparty, 'Ana Torres Vega');
      expect(p.operationId, '3f2a9c10-7b1d-4e55-9a01-0c1d2e3f4a5b');
    });

    test('un importe grande con cuatro decimales', () {
      final p = parse(kLemonMail.replaceAll('4.0000', '1,250.5000'))!;
      expect(p.amountMinor, 125050);
    });

    test('un destinatario N/A no es destinatario', () {
      expect(parse(kLemonMail.replaceAll('Ana Torres Vega', 'N/A'))!.counterparty, isNull);
    });

    test('el asunto solo también se entiende', () {
      final p = parse('Enviaste S/ 4 💸')!;
      expect(p.amountMinor, 400);
      expect(p.direction, CaptureDirection.out);
    });

    test('sin operación reconocible no toma ni CCI ni ID externo', () {
      const fields = 'CCI: 00219300000000000011\nID externo: 1234567890123456789012345678';
      expect(parse(fields), isNull);
    });
  });

  group('regla genérica', () {
    test('otra entidad con su propio formato', () {
      final p = parse('Interbank: Consumo Tarjeta Débito ***4321 por S/ 89.90 en CINEPLANET. Saldo: S/ 1,000.00. Ref: 778899')!;
      expect(p.amountMinor, 8990);
      expect(p.direction, CaptureDirection.out);
      expect(p.counterparty, 'CINEPLANET');
      expect(p.accountDigits, '4321');
      expect(p.operationId, '778899');
    });
  });

  group('accountSearchText', () {
    test('no deja ver el destinatario ni su entidad', () {
      final p = parse(kLemonMail)!;
      final s = accountSearchText(kLemonMail, p).toLowerCase();
      expect(s, isNot(contains('bcp')));
      expect(s, isNot(contains('ana torres')));
    });

    test('no deja ver a quién se envió', () {
      const t = 'Scotiabank: transferiste S/ 20.00 a Dale';
      final s = accountSearchText(t, parse(t)!);
      expect(s, contains('Scotiabank'));
      expect(s, isNot(contains('Dale')));
    });
  });
}
