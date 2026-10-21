import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/billing_cycle.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/merchants/domain/entities/merchant.dart';
import 'package:outflow/features/subscriptions/domain/entities/subscription.dart';
import 'package:outflow/features/wallet/domain/month_summary.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';

var _seq = 0;

Movement mv(MovementKind kind, int major, DateTime date, {String currency = 'PEN', String cat = 'food'}) =>
    Movement(
      id: 'm${_seq++}',
      kind: kind,
      amount: Money(major * 100, currency),
      categoryId: cat,
      date: date,
      createdAt: date,
    );

Movement exp(int major, DateTime date, {String currency = 'PEN', String cat = 'food'}) =>
    mv(MovementKind.expense, major, date, currency: currency, cat: cat);
Movement inc(int major, DateTime date) => mv(MovementKind.income, major, date);

Subscription sub({required DateTime next, int minor = 2990, SubscriptionStatus status = SubscriptionStatus.active}) =>
    Subscription(
      id: 'netflix',
      merchantId: 'netflix',
      name: 'Netflix',
      price: Money(minor, 'PEN'),
      cycle: const BillingCycle.monthly(),
      firstChargeDate: next,
      category: SpendCategory.streaming,
      paymentMethod: const PaymentMethod(kind: PaymentKind.card),
      createdAt: DateTime(2026, 1, 1),
      status: status,
    );

void main() {
  final settings = WalletSettings(walletStartedAt: DateTime(2026, 9, 1));
  final oct = DateTime(2026, 10);
  final now = DateTime(2026, 10, 20, 12);

  MonthSummary compute(List<Movement> ms, {DateTime? month, WalletSettings? s, List<Subscription> subs = const []}) =>
      MonthSummary.compute(
        movements: ms,
        subscriptions: subs,
        settings: s ?? settings,
        month: month ?? oct,
        now: now,
      );

  test('remaining = ingresos − gastos del mes', () {
    final s = compute([inc(2000, DateTime(2026, 10, 2)), exp(300, DateTime(2026, 10, 5)), exp(200, DateTime(2026, 10, 9))]);
    expect(s.income, const Money(200000, 'PEN'));
    expect(s.expense, const Money(50000, 'PEN'));
    expect(s.remaining, const Money(150000, 'PEN'));
    expect(s.hasIncome, isTrue);
    expect(s.spentRatio, closeTo(0.25, 1e-9));
  });

  test('límite de mes: el 31 a las 23:59 cuenta en octubre y el 1 a las 00:00 en noviembre', () {
    final ms = [exp(10, DateTime(2026, 10, 31, 23, 59)), exp(7, DateTime(2026, 11, 1))];
    expect(compute(ms).expense, const Money(1000, 'PEN'));
    expect(compute(ms, month: DateTime(2026, 11)).expense, const Money(700, 'PEN'));
  });

  test('el sobrante positivo pasa al mes siguiente si está activado', () {
    final ms = [inc(2000, DateTime(2026, 10, 2)), exp(500, DateTime(2026, 10, 5)), exp(100, DateTime(2026, 11, 3))];
    final nov = compute(ms, month: DateTime(2026, 11));
    expect(nov.carriedIn, const Money(150000, 'PEN'));
    expect(nov.remaining, const Money(140000, 'PEN'));
    expect(nov.hasIncome, isTrue);
  });

  test('el sobrante se encadena por varios meses', () {
    final ms = [inc(1000, DateTime(2026, 9, 2)), exp(100, DateTime(2026, 9, 3)), inc(50, DateTime(2026, 10, 1))];
    expect(compute(ms, month: DateTime(2026, 11)).carriedIn, const Money(95000, 'PEN'));
  });

  test('un sobrante negativo no pasa; con el ajuste apagado tampoco', () {
    final negative = [inc(100, DateTime(2026, 10, 2)), exp(300, DateTime(2026, 10, 5))];
    expect(compute(negative, month: DateTime(2026, 11)).carriedIn, const Money(0, 'PEN'));
    final positive = [inc(2000, DateTime(2026, 10, 2))];
    final off = settings.copyWith(carryOver: false);
    expect(compute(positive, month: DateTime(2026, 11), s: off).carriedIn, const Money(0, 'PEN'));
  });

  test('nada antes del mes en que empezó la wallet', () {
    final ms = [inc(5000, DateTime(2026, 8, 2))];
    expect(compute(ms, month: DateTime(2026, 9)).carriedIn, const Money(0, 'PEN'));
  });

  test('otras monedas no suman y se listan aparte como neto gastado', () {
    final s = compute([inc(1000, DateTime(2026, 10, 2)), exp(15, DateTime(2026, 10, 3), currency: 'USD')]);
    expect(s.remaining, const Money(100000, 'PEN'));
    expect(s.otherCurrencies, [const Money(1500, 'USD')]);
  });

  test('afterPending resta Netflix (29.90, día 25) visto el día 20', () {
    final s = compute([inc(1000, DateTime(2026, 10, 2))], subs: [sub(next: DateTime(2026, 10, 25))]);
    expect(s.afterPending, const Money(100000 - 2990, 'PEN'));
  });

  test('afterPending ignora pruebas gratuitas, cobros de hoy y del mes siguiente', () {
    final s = compute(
      [inc(1000, DateTime(2026, 10, 2))],
      subs: [
        sub(next: DateTime(2026, 10, 25), status: SubscriptionStatus.trial),
        sub(next: DateTime(2026, 10, 20)),
        sub(next: DateTime(2026, 11, 2)),
      ],
    );
    expect(s.afterPending, s.remaining);
  });

  test('sin ingresos: hasIncome false y spentRatio 0', () {
    final s = compute([exp(120, DateTime(2026, 10, 2))]);
    expect(s.hasIncome, isFalse);
    expect(s.spentRatio, 0);
    expect(s.expense, const Money(12000, 'PEN'));
  });

  test('gasto por categoría', () {
    final s = compute([exp(300, DateTime(2026, 10, 2)), exp(100, DateTime(2026, 10, 3), cat: 'transport')]);
    expect(s.expenseByCategory, {'food': const Money(30000, 'PEN'), 'transport': const Money(10000, 'PEN')});
  });

  test('lastMonths devuelve los n meses terminando en el pedido, el más antiguo primero', () {
    final list = MonthSummary.lastMonths(
      3,
      movements: [inc(10, DateTime(2026, 9, 2))],
      subscriptions: const [],
      settings: settings,
      month: oct,
      now: now,
    );
    expect(list.map((m) => m.month), [DateTime(2026, 8), DateTime(2026, 9), DateTime(2026, 10)]);
    expect(list[1].income, const Money(1000, 'PEN'));
  });
}
