import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/billing_cycle.dart';
import 'package:outflow/features/subscriptions/domain/charge_pattern.dart';

void main() {
  const monthly = BillingCycle.monthly();

  group('ChargePattern.nextAfter', () {
    test('mismo día: el 31 se recorta en febrero y vuelve al 31 en marzo', () {
      const p = ChargePattern.sameDay(31);
      final feb = p.nextAfter(DateTime(2026, 1, 31), monthly);
      expect(feb, DateTime(2026, 2, 28));
      expect(p.nextAfter(feb, monthly), DateTime(2026, 3, 31));
    });

    test('cada N días suma días exactos', () {
      expect(const ChargePattern.everyNDays(30).nextAfter(DateTime(2026, 1, 18), monthly),
          DateTime(2026, 2, 17));
    });

    test('día hábil: domingo 31 may pasa al lunes 1 jun y luego vuelve al 30 jun', () {
      const p = ChargePattern.businessDay(31);
      final jun1 = p.nextAfter(DateTime(2026, 4, 30), monthly);
      expect(jun1, DateTime(2026, 6, 1));
      expect(p.nextAfter(jun1, monthly), DateTime(2026, 6, 30));
    });

    test('día hábil: sábado 18 abr pasa al lunes 20', () {
      expect(const ChargePattern.businessDay(18).nextAfter(DateTime(2026, 3, 18), monthly),
          DateTime(2026, 4, 20));
    });

    test('mismo día anual', () {
      expect(const ChargePattern.sameDay(29).nextAfter(DateTime(2028, 2, 29), const BillingCycle.yearly()),
          DateTime(2029, 2, 28));
    });

    test('mismo día semanal suma semanas', () {
      expect(
        const ChargePattern.sameDay(5).nextAfter(DateTime(2026, 10, 5), const BillingCycle(unit: CycleUnit.week, every: 2)),
        DateTime(2026, 10, 19),
      );
    });
  });

  test('JSON ida y vuelta', () {
    for (final p in const [ChargePattern.sameDay(18), ChargePattern.everyNDays(30), ChargePattern.businessDay(5)]) {
      expect(ChargePattern.fromJson(p.toJson()), p);
    }
  });

  test('describe', () {
    expect(const ChargePattern.sameDay(18).describe(monthly), 'Mismo día de cada mes (18)');
    expect(const ChargePattern.everyNDays(30).describe(monthly), 'Cada 30 días');
    expect(const ChargePattern.businessDay(18).describe(monthly), 'Día 18 o siguiente día hábil');
  });
}
