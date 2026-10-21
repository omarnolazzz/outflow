import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/billing_cycle.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/merchants/domain/entities/merchant.dart';
import 'package:outflow/features/subscriptions/domain/charge_pattern.dart';
import 'package:outflow/features/subscriptions/domain/charges_in_month.dart';
import 'package:outflow/features/subscriptions/domain/entities/subscription.dart';

Subscription sub(
  String id, {
  required DateTime anchor,
  BillingCycle cycle = const BillingCycle.monthly(),
  ChargePattern? pattern,
  SubscriptionStatus status = SubscriptionStatus.active,
  List<ChargeRecord> history = const [],
}) =>
    Subscription(
      id: id,
      merchantId: id,
      name: id,
      price: const Money(1000, 'PEN'),
      cycle: cycle,
      firstChargeDate: anchor,
      category: SpendCategory.other,
      paymentMethod: const PaymentMethod(kind: PaymentKind.card),
      createdAt: DateTime(2026, 1, 1),
      status: status,
      chargeHistory: history,
      chargePattern: pattern,
    );

void main() {
  final oct = DateTime(2026, 10);

  test('una suscripción mensual del 18 cae el 18', () {
    final m = chargesInMonth([sub('netflix', anchor: DateTime(2026, 10, 18))], oct);
    expect(m.keys, [DateTime(2026, 10, 18)]);
    expect(m[DateTime(2026, 10, 18)]!.single.id, 'netflix');
  });

  test('"cada 30 días" desde el 1 cae el 1 y el 31', () {
    final s = sub('gym', anchor: DateTime(2026, 10, 1), pattern: const ChargePattern.everyNDays(30));
    expect(chargesInMonth([s], oct).keys, [DateTime(2026, 10, 1), DateTime(2026, 10, 31)]);
  });

  test('incluye los cobros del historial aunque el ancla ya esté en el mes siguiente', () {
    final s = sub(
      'spotify',
      anchor: DateTime(2026, 11, 9),
      history: [ChargeRecord(date: DateTime(2026, 10, 9), confirmed: true)],
    );
    expect(chargesInMonth([s], oct).keys, [DateTime(2026, 10, 9)]);
  });

  test('pausadas o canceladas solo muestran su historial', () {
    final s = sub(
      'max',
      anchor: DateTime(2026, 10, 25),
      status: SubscriptionStatus.paused,
      history: [ChargeRecord(date: DateTime(2026, 10, 2), confirmed: true)],
    );
    expect(chargesInMonth([s], oct).keys, [DateTime(2026, 10, 2)]);
  });

  test('dos suscripciones el mismo día se agrupan', () {
    final m = chargesInMonth([
      sub('a', anchor: DateTime(2026, 10, 5)),
      sub('b', anchor: DateTime(2026, 10, 5)),
    ], oct);
    expect(m[DateTime(2026, 10, 5)]!.map((s) => s.id), ['a', 'b']);
  });
}
