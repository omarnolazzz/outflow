import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/billing_cycle.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/merchants/domain/entities/merchant.dart';
import 'package:outflow/features/notifications/domain/charge_answer.dart';
import 'package:outflow/features/subscriptions/data/subscription_model.dart';
import 'package:outflow/features/subscriptions/domain/apply_charge_answer.dart';
import 'package:outflow/features/subscriptions/domain/charge_pattern.dart';
import 'package:outflow/features/subscriptions/domain/charge_schedule.dart';
import 'package:outflow/features/subscriptions/domain/entities/subscription.dart';

Subscription sub({
  DateTime? anchor,
  SubscriptionStatus status = SubscriptionStatus.active,
  List<ChargeRecord> history = const [],
  ChargePattern? pattern,
}) =>
    Subscription(
      id: 's1',
      merchantId: 'cat.netflix',
      name: 'Netflix',
      price: const Money(1549, 'USD'),
      cycle: const BillingCycle.monthly(),
      firstChargeDate: anchor ?? DateTime(2026, 10, 18),
      category: SpendCategory.streaming,
      paymentMethod: const PaymentMethod(kind: PaymentKind.card),
      createdAt: DateTime(2026, 10, 1),
      status: status,
      chargeHistory: history,
      chargePattern: pattern,
    );

ChargeRecord confirmed(int y, int m, int d) => ChargeRecord(date: DateTime(y, m, d), confirmed: true);

void main() {
  group('pendingCharge', () {
    test('el día siguiente al cobro previsto hay pregunta pendiente', () {
      expect(sub().pendingCharge(DateTime(2026, 10, 19, 9)), DateTime(2026, 10, 18));
    });

    test('el mismo día del cobro todavía no se pregunta', () {
      expect(sub().pendingCharge(DateTime(2026, 10, 18, 23)), isNull);
    });

    test('pausada o cancelada no pregunta', () {
      expect(sub(status: SubscriptionStatus.paused).pendingCharge(DateTime(2026, 10, 19)), isNull);
      expect(sub(status: SubscriptionStatus.cancelled).pendingCharge(DateTime(2026, 10, 19)), isNull);
    });

    test('sin responder varios ciclos: solo la más reciente queda pendiente y la proyección sigue', () {
      final s = sub();
      final now = DateTime(2026, 12, 20);
      expect(s.pendingCharge(now), DateTime(2026, 12, 18));
      expect(s.nextCharge(now), DateTime(2027, 1, 18));
      expect(s.lastCharge(now), DateTime(2026, 12, 18));
    });
  });

  group('confirmCharge', () {
    test('los ciclos sin respuesta pasan al historial como asumidos', () {
      final s = sub().confirmCharge(
        pending: DateTime(2026, 12, 18),
        chargedOn: DateTime(2026, 12, 18),
        next: DateTime(2027, 1, 18),
      );
      expect(s.chargeHistory.map((r) => (r.date, r.confirmed)), [
        (DateTime(2026, 10, 18), false),
        (DateTime(2026, 11, 18), false),
        (DateTime(2026, 12, 18), true),
      ]);
      expect(s.firstChargeDate, DateTime(2027, 1, 18));
      expect(s.pendingCharge(DateTime(2026, 12, 20)), isNull);
    });

    test('el patrón elegido se guarda', () {
      final s = sub().confirmCharge(
        pending: DateTime(2026, 10, 18),
        chargedOn: DateTime(2026, 10, 18),
        next: DateTime(2026, 11, 17),
        pattern: const ChargePattern.everyNDays(30),
      );
      expect(s.pattern, const ChargePattern.everyNDays(30));
      expect(s.nextCharge(DateTime(2026, 11, 18)), DateTime(2026, 12, 17));
    });

    test('una fecha propia sin patrón detectable reajusta el día del patrón', () {
      final s = sub().confirmCharge(
        pending: DateTime(2026, 10, 18),
        chargedOn: DateTime(2026, 10, 18),
        next: DateTime(2026, 11, 20),
      );
      expect(s.pattern, const ChargePattern.sameDay(20));
    });
  });

  group('suggestNext', () {
    test('mismo día primero, luego cada 30 días; sin duplicados y como máximo 3', () {
      final list = suggestNext(sub(), DateTime(2026, 10, 18));
      expect(list.map((s) => s.date), [DateTime(2026, 11, 18), DateTime(2026, 11, 17)]);
      expect(list.map((s) => s.label), ['Mismo día del mes', 'Cada 30 días']);
    });

    test('con patrón "cada 30 días" aprendido, esa sugerencia va primero', () {
      final list = suggestNext(sub(pattern: const ChargePattern.everyNDays(30)), DateTime(2026, 10, 18));
      expect(list.first.date, DateTime(2026, 11, 17));
      expect(list.first.pattern, const ChargePattern.everyNDays(30));
    });

    test('incluye el siguiente día hábil cuando el mismo día cae en fin de semana', () {
      // 18 abr 2026 es sábado.
      final list = suggestNext(sub(anchor: DateTime(2026, 3, 18)), DateTime(2026, 3, 18));
      expect(list.map((s) => s.date), contains(DateTime(2026, 4, 20)));
      expect(list.length, lessThanOrEqualTo(3));
    });
  });

  group('inferPattern', () {
    const monthly = BillingCycle.monthly();

    test('intervalos iguales → cada N días (caso de la tarjeta de crédito)', () {
      expect(inferPattern([confirmed(2026, 1, 18), confirmed(2026, 2, 17), confirmed(2026, 3, 19)], monthly),
          const ChargePattern.everyNDays(30));
    });

    test('mismo día del mes → sameDay', () {
      expect(inferPattern([confirmed(2026, 1, 18), confirmed(2026, 2, 18), confirmed(2026, 3, 18)], monthly),
          const ChargePattern.sameDay(18));
    });

    test('meses de 31 y 30 días con el mismo día no se confunden con cada 30 días', () {
      expect(inferPattern([confirmed(2026, 3, 18), confirmed(2026, 4, 18), confirmed(2026, 5, 18)], monthly),
          const ChargePattern.sameDay(18));
    });

    test('fin de semana desplazado al lunes → día hábil', () {
      // 18 abr 2026 sábado → 20 abr.
      expect(inferPattern([confirmed(2026, 4, 20), confirmed(2026, 5, 18), confirmed(2026, 6, 18)], monthly),
          const ChargePattern.businessDay(18));
    });

    test('los cobros asumidos no cuentan', () {
      expect(
        inferPattern([
          confirmed(2026, 1, 18),
          ChargeRecord(date: DateTime(2026, 2, 17), confirmed: false),
          confirmed(2026, 3, 19),
        ], monthly),
        isNull,
      );
    });
  });

  group('applyChargeAnswer', () {
    final now = DateTime(2026, 10, 19, 10);
    ChargeAnswer answer(ChargeAnswerAction action, [DateTime? next]) =>
        ChargeAnswer(subscriptionId: 's1', charge: DateTime(2026, 10, 18), action: action, next: next);

    test('"Sí" confirma el cobro y adopta el patrón de la sugerencia', () {
      final s = applyChargeAnswer(sub(), answer(ChargeAnswerAction.yes, DateTime(2026, 11, 18)), now)!;
      expect(s.firstChargeDate, DateTime(2026, 11, 18));
      expect(s.chargeHistory.single.confirmed, isTrue);
      expect(s.pattern, const ChargePattern.sameDay(18));
    });

    test('"2ª fecha" con cada 30 días aprende ese patrón', () {
      final s = applyChargeAnswer(sub(), answer(ChargeAnswerAction.alt, DateTime(2026, 11, 17)), now)!;
      expect(s.pattern, const ChargePattern.everyNDays(30));
    });

    test('una respuesta a un cobro ya confirmado se ignora', () {
      final done = applyChargeAnswer(sub(), answer(ChargeAnswerAction.yes, DateTime(2026, 11, 18)), now)!;
      expect(applyChargeAnswer(done, answer(ChargeAnswerAction.alt, DateTime(2026, 11, 17)), now), isNull);
    });

    test('"Ya la cancelé" cancela la suscripción', () {
      final s = applyChargeAnswer(sub(), answer(ChargeAnswerAction.cancel), now)!;
      expect(s.status, SubscriptionStatus.cancelled);
      expect(s.pendingCharge(now), isNull);
    });
  });

  group('persistencia', () {
    test('historial y patrón sobreviven a JSON', () {
      final s = sub(history: [confirmed(2026, 9, 18)], pattern: const ChargePattern.businessDay(18));
      final back = SubscriptionModel.fromJson(SubscriptionModel.toJson(s));
      expect(back.chargeHistory.single.date, DateTime(2026, 9, 18));
      expect(back.chargeHistory.single.confirmed, isTrue);
      expect(back.chargePattern, const ChargePattern.businessDay(18));
    });

    test('datos v1 sin campos nuevos: historial vacío y patrón por defecto', () {
      final json = SubscriptionModel.toJson(sub())
        ..remove('chargeHistory')
        ..remove('chargePattern')
        ..['v'] = 1;
      final back = SubscriptionModel.fromJson(json);
      expect(back.chargeHistory, isEmpty);
      expect(back.pattern, const ChargePattern.sameDay(18));
    });

    test('ancla en día 31 sin patrón: 28 feb y vuelve a 31 mar', () {
      final s = sub(anchor: DateTime(2026, 1, 31));
      expect(s.nextCharge(DateTime(2026, 2, 1)), DateTime(2026, 2, 28));
      expect(s.nextCharge(DateTime(2026, 3, 1)), DateTime(2026, 3, 31));
    });
  });
}
