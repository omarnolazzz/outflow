import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/billing_cycle.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/merchants/domain/entities/merchant.dart';
import 'package:outflow/features/notifications/domain/notification_rule.dart';
import 'package:outflow/features/notifications/domain/reminder_planner.dart';
import 'package:outflow/features/subscriptions/data/subscription_model.dart';
import 'package:outflow/features/subscriptions/domain/dashboard_summary.dart';
import 'package:outflow/features/subscriptions/domain/entities/subscription.dart';

Subscription sub({
  DateTime? first,
  BillingCycle cycle = const BillingCycle.monthly(),
  CancellationWindow? window,
  NotificationRule? rule,
  SubscriptionStatus status = SubscriptionStatus.active,
}) =>
    Subscription(
      id: 's1',
      merchantId: 'cat.netflix',
      name: 'Netflix',
      price: const Money(1549, 'USD'),
      cycle: cycle,
      firstChargeDate: first ?? DateTime(2026, 1, 31),
      category: SpendCategory.streaming,
      paymentMethod: const PaymentMethod(kind: PaymentKind.card, label: 'Visa', last4: '4242'),
      createdAt: DateTime(2026, 1, 1),
      cancellationWindow: window,
      notificationRule: rule,
      status: status,
    );

void main() {
  group('BillingCycle', () {
    test('mensual desde el 31 se ajusta a fin de mes sin deriva', () {
      const c = BillingCycle.monthly();
      final a = DateTime(2026, 1, 31);
      expect(c.occurrence(a, 1), DateTime(2026, 2, 28));
      expect(c.occurrence(a, 2), DateTime(2026, 3, 31));
      expect(c.occurrence(a, 3), DateTime(2026, 4, 30));
    });

    test('nextOnOrAfter devuelve el mismo día si hoy hay cobro', () {
      const c = BillingCycle.monthly();
      expect(c.nextOnOrAfter(DateTime(2026, 1, 15), DateTime(2026, 10, 15, 18)), DateTime(2026, 10, 15));
      expect(c.nextOnOrAfter(DateTime(2026, 1, 15), DateTime(2026, 10, 16)), DateTime(2026, 11, 15));
    });

    test('previousBefore', () {
      const c = BillingCycle(unit: CycleUnit.week, every: 2);
      final a = DateTime(2026, 10, 1);
      expect(c.previousBefore(a, DateTime(2026, 10, 20)), DateTime(2026, 10, 15));
      expect(c.previousBefore(a, DateTime(2026, 10, 1)), isNull);
    });

    test('anual en 29 de febrero', () {
      const c = BillingCycle.yearly();
      expect(c.occurrence(DateTime(2028, 2, 29), 1), DateTime(2029, 2, 28));
      expect(c.occurrence(DateTime(2028, 2, 29), 4), DateTime(2032, 2, 29));
    });
  });

  group('Ventana de cancelación', () {
    test('después del cobro: abierta hasta cobro + N días', () {
      final s = sub(first: DateTime(2026, 10, 15), window: const CancellationWindow(days: 7));
      final open = s.openWindow(DateTime(2026, 10, 19));
      expect(open?.chargeDate, DateTime(2026, 10, 15));
      expect(open?.deadline, DateTime(2026, 10, 22));
      expect(s.openWindow(DateTime(2026, 10, 23)), isNull);
    });

    test('un cobro de hoy ya abre la ventana', () {
      final s = sub(first: DateTime(2026, 9, 19), window: const CancellationWindow(days: 3));
      expect(s.openWindow(DateTime(2026, 10, 19))?.chargeDate, DateTime(2026, 10, 19));
    });

    test('cancelada no tiene ventana', () {
      final s = sub(
        first: DateTime(2026, 10, 15),
        window: const CancellationWindow(days: 7),
        status: SubscriptionStatus.cancelled,
      );
      expect(s.openWindow(DateTime(2026, 10, 16)), isNull);
    });
  });

  group('NotificationRule', () {
    test('10 días antes todos los días', () {
      const r = NotificationRule(leadDays: 10, repeatEveryDays: 1, remindOnChargeDay: false);
      expect(r.chargeOffsets, [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]);
    });

    test('10 días antes dejando 2 días entre avisos', () {
      const r = NotificationRule(leadDays: 10, repeatEveryDays: 3);
      expect(r.chargeOffsets, [10, 7, 4, 1, 0]);
    });

    test('avisos puntuales se combinan sin duplicados', () {
      const r = NotificationRule(leadDays: 3, customOffsets: {30, 3}, remindOnChargeDay: false);
      expect(r.chargeOffsets, [30, 3, 2, 1]);
    });

    test('JSON ida y vuelta', () {
      const r = NotificationRule(leadDays: 5, repeatEveryDays: 2, customOffsets: {14}, hour: 20, minute: 30);
      expect(NotificationRule.fromJson(r.toJson()).toJson(), r.toJson());
    });
  });

  group('ReminderPlanner', () {
    const planner = ReminderPlanner();

    test('genera avisos a la hora configurada y solo en el futuro', () {
      final s = sub(first: DateTime(2026, 10, 25));
      const rule = NotificationRule(leadDays: 3, hour: 9);
      final plan = planner.planFor(
        s,
        rule,
        now: DateTime(2026, 10, 22, 10), // 22 oct 09:00 ya pasó
        until: DateTime(2026, 10, 31),
      );
      expect(plan.map((r) => r.fireAt), [
        DateTime(2026, 10, 23, 9),
        DateTime(2026, 10, 24, 9),
        DateTime(2026, 10, 25, 9),
      ]);
      expect(plan.last.kind, ReminderKind.chargeDay);
    });

    test('avisa del cierre de ventana de un cobro ya hecho', () {
      final s = sub(first: DateTime(2026, 10, 15), window: const CancellationWindow(days: 7));
      const rule = NotificationRule(leadDays: 0, remindOnChargeDay: false, deadlineLeadDays: 1);
      final plan = planner.planFor(s, rule, now: DateTime(2026, 10, 19), until: DateTime(2026, 11, 1));
      expect(plan.single.kind, ReminderKind.cancellationDeadline);
      expect(plan.single.fireAt, DateTime(2026, 10, 21, 9));
    });

    test('respeta la regla propia sobre la global y omite pausadas', () {
      final own = sub(first: DateTime(2026, 10, 30), rule: const NotificationRule(enabled: false));
      final paused = sub(first: DateTime(2026, 10, 30), status: SubscriptionStatus.paused);
      final plan = planner.plan(
        subscriptions: [own, paused],
        globalRule: const NotificationRule(),
        now: DateTime(2026, 10, 19),
      );
      expect(plan, isEmpty);
    });

    test('nunca supera el límite de iOS', () {
      final daily = sub(first: DateTime(2026, 1, 1), cycle: const BillingCycle(unit: CycleUnit.day));
      final plan = planner.plan(
        subscriptions: [daily],
        globalRule: const NotificationRule(leadDays: 2),
        now: DateTime(2026, 10, 19),
      );
      expect(plan.length, lessThanOrEqualTo(60));
    });
  });

  test('DashboardSummary ordena próximos y suma por moneda', () {
    final a = sub(first: DateTime(2026, 10, 21));
    final b = sub(first: DateTime(2026, 10, 30), cycle: const BillingCycle.yearly());
    final summary = DashboardSummary.compute([b, a], DateTime(2026, 10, 19));
    expect(summary.upcoming.first.date, DateTime(2026, 10, 21));
    expect(summary.upcoming.first.urgency, Urgency.soon);
    expect(summary.primaryMonthly!.currency, 'USD');
    expect(summary.billingCount, 2);
  });

  test('la moneda principal es la más usada, no la de mayor importe nominal', () {
    final usd1 = sub(first: DateTime(2026, 10, 21));
    final usd2 = sub(first: DateTime(2026, 10, 22));
    final mxn = Subscription(
      id: 'mx',
      merchantId: 'cat.telcel',
      name: 'Telcel',
      price: const Money(49900, 'MXN'),
      cycle: const BillingCycle.monthly(),
      firstChargeDate: DateTime(2026, 10, 28),
      category: SpendCategory.mobile,
      paymentMethod: const PaymentMethod(kind: PaymentKind.bank),
      createdAt: DateTime(2026, 1, 1),
    );
    final summary = DashboardSummary.compute([mxn, usd1, usd2], DateTime(2026, 10, 19));
    expect(summary.primaryMonthly!.currency, 'USD');
  });

  test('SubscriptionModel JSON ida y vuelta', () {
    final s = sub(window: const CancellationWindow(days: 5, policy: CancellationPolicy.beforeCharge));
    final back = SubscriptionModel.fromJson(SubscriptionModel.toJson(s));
    expect(SubscriptionModel.toJson(back), SubscriptionModel.toJson(s));
  });
}
