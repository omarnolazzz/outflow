import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/expense_hints.dart';
import 'package:outflow/features/wallet/domain/movement.dart';

Movement mv(String title, int minor, DateTime at, {String cat = 'food', MovementOrigin origin = MovementOrigin.manual}) =>
    Movement(
      id: '$title$at',
      kind: MovementKind.expense,
      amount: Money(minor, 'PEN'),
      categoryId: cat,
      date: at,
      createdAt: at,
      title: title,
      origin: origin,
    );

void main() {
  final now = DateTime(2026, 10, 22, 13, 0);
  final cats = defaultCategories();

  test('normalizeMerchant ignora mayúsculas, acentos y espacios', () {
    expect(normalizeMerchant('  STARBÚCKS   Perú '), 'starbucks peru');
  });

  test('recuerda la categoría usada antes con el mismo comercio', () {
    final history = [mv('Starbucks', 1500, now.subtract(const Duration(days: 3)), cat: 'leisure')];
    expect(suggestCategory(merchant: 'STARBUCKS PERU', history: history, categories: cats), 'leisure');
  });

  test('el comercio exacto gana a otro que empieza igual', () {
    final history = [
      mv('Plaza Vea', 5000, now.subtract(const Duration(days: 9)), cat: 'groceries'),
      mv('Plaza San Miguel', 9000, now.subtract(const Duration(days: 1)), cat: 'shopping'),
    ];
    expect(suggestCategory(merchant: 'PLAZA VEA', history: history, categories: cats), 'groceries');
  });

  test('una primera palabra genérica no basta para recordar', () {
    final history = [mv('La Lucha Sanguchería', 3000, now, cat: 'leisure')];
    expect(suggestCategory(merchant: 'La Bodega del Barrio', history: history, categories: cats), isNull);
  });

  test('sin historial usa palabras clave', () {
    expect(suggestCategory(merchant: 'Plaza Vea Surco', history: const [], categories: cats), 'groceries');
    expect(suggestCategory(merchant: 'UBER *TRIP', history: const [], categories: cats), 'transport');
    expect(suggestCategory(merchant: 'Inkafarma', history: const [], categories: cats), 'health');
  });

  test('comercio desconocido sin historial → null', () {
    expect(suggestCategory(merchant: 'Ferretería Don Pepe', history: const [], categories: cats), isNull);
    expect(suggestCategory(merchant: '', history: const [], categories: cats), isNull);
  });

  test('no sugiere categorías que ya no existen', () {
    final history = [mv('Starbucks', 1500, now, cat: 'borrada')];
    expect(suggestCategory(merchant: 'Starbucks', history: history, categories: cats), 'food');
  });

  test('posible duplicado: mismo importe y comercio en los últimos 2 minutos', () {
    final recent = mv('Starbucks', 1250, now.subtract(const Duration(minutes: 1)), origin: MovementOrigin.applePay);
    final old = mv('Starbucks', 1250, now.subtract(const Duration(minutes: 5)));
    final other = mv('Starbucks', 1300, now.subtract(const Duration(seconds: 30)));
    expect(findRecentDuplicate(movements: [recent], amountMinor: 1250, merchant: 'STARBUCKS', now: now), recent);
    expect(findRecentDuplicate(movements: [old], amountMinor: 1250, merchant: 'Starbucks', now: now), isNull);
    expect(findRecentDuplicate(movements: [other], amountMinor: 1250, merchant: 'Starbucks', now: now), isNull);
  });
}
