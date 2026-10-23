import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/payment_match.dart';

Movement mv(String id, String title, int minor, DateTime at, {MovementOrigin origin = MovementOrigin.applePay}) => Movement(
      id: id,
      kind: MovementKind.expense,
      amount: Money(minor, 'PEN'),
      categoryId: 'food',
      date: at,
      createdAt: at,
      title: title,
      origin: origin,
    );

void main() {
  final when = DateTime(2026, 10, 20, 18, 30);

  List<String> match(List<Movement> ms, {int amount = 4590, String? merchant = 'Bodega San Martín'}) =>
      findMatchingPayments(movements: ms, amountMinor: amount, merchant: merchant, date: when).map((m) => m.id).toList();

  test('el pago de Apple Pay de hace una hora coincide', () {
    expect(match([mv('a', 'BODEGA SAN MARTIN', 4590, when.subtract(const Duration(hours: 1)))]), ['a']);
  });

  test('un importe a menos del 1 % coincide aunque el comercio se llame distinto', () {
    expect(match([mv('a', 'POS 123', 4620, when)]), ['a']);
  });

  test('otro importe y otro comercio no coincide; hace 5 días tampoco', () {
    expect(match([mv('a', 'Tambo', 6000, when)]), isEmpty);
    expect(match([mv('b', 'Bodega San Martín', 4590, when.subtract(const Duration(days: 5)))]), isEmpty);
  });

  test('mismo comercio con otro importe coincide (el ticket corrige el importe)', () {
    expect(match([mv('a', 'Bodega San Martin', 3000, when)]), ['a']);
  });

  test('no ofrece cobros de suscripciones ni ingresos, y ordena por cercanía', () {
    final sub = mv('s', 'Bodega San Martín', 4590, when, origin: MovementOrigin.subscription);
    final far = mv('far', 'Bodega San Martín', 4590, when.subtract(const Duration(days: 2)));
    final near = mv('near', 'Bodega San Martín', 4590, when.subtract(const Duration(minutes: 10)));
    expect(match([sub, far, near]), ['near', 'far']);
  });

  test('tu parte de un gasto compartido nunca coincide', () {
    final share = mv('sp', 'Bodega San Martín', 4590, when, origin: MovementOrigin.split);
    expect(match([share]), isEmpty);
  });
}
