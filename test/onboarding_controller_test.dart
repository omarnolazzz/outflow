import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/onboarding/presentation/onboarding_controller.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';

import 'support/fakes.dart';

void main() {
  late MemorySettings settings;
  late MemoryMovements movements;

  setUp(() {
    settings = MemorySettings();
    movements = MemoryMovements();
  });

  OnboardingController make({bool short = false}) =>
      OnboardingController(short: short, settings: settings, movements: movements);

  test('el flujo completo tiene 7 pasos y el corto 5, ambos empiezan en moneda', () {
    expect(make().steps, [
      OnboardingStep.currency,
      OnboardingStep.startingBalance,
      OnboardingStep.carryOver,
      OnboardingStep.subscriptions,
      OnboardingStep.notifications,
      OnboardingStep.faceId,
      OnboardingStep.done,
    ]);
    expect(make(short: true).steps, [
      OnboardingStep.currency,
      OnboardingStep.startingBalance,
      OnboardingStep.carryOver,
      OnboardingStep.faceId,
      OnboardingStep.done,
    ]);
    expect(make().step, OnboardingStep.currency);
  });

  test('next y back recorren los pasos sin salirse', () {
    final c = make(short: true);
    c.back();
    expect(c.index, 0);
    for (var i = 0; i < 10; i++) {
      c.next();
    }
    expect(c.step, OnboardingStep.done);
    expect(c.progress, 1);
    c.back();
    expect(c.step, OnboardingStep.faceId);
  });

  test('por defecto: PEN, sobrante activo, sin saldo inicial ni Face ID', () {
    final c = make();
    expect(c.currency, 'PEN');
    expect(c.carryOver, isTrue);
    expect(c.startingBalanceMinor, 0);
    expect(c.faceId, isFalse);
  });

  test('complete guarda los ajustes y crea "Saldo inicial" cuando es mayor que 0', () async {
    final now = DateTime(2026, 10, 21, 9);
    final c = make()
      ..setCurrency('USD')
      ..setStartingBalance(150000)
      ..setCarryOver(false)
      ..setFaceId(true);
    await c.complete(now);

    final s = settings.read();
    expect(s.currency, 'USD');
    expect(s.carryOver, isFalse);
    expect(s.faceIdEnabled, isTrue);
    expect(s.onboardingDone, isTrue);
    expect(s.walletStartedAt, now);

    final m = movements.saved.single;
    expect(m.kind, MovementKind.income);
    expect(m.origin, MovementOrigin.initialBalance);
    expect(m.title, 'Saldo inicial');
    expect(m.categoryId, kOtherIncomeCategoryId);
    expect(m.amount, const Money(150000, 'USD'));
    expect(m.date, now);
  });

  test('sin saldo inicial no crea movimientos', () async {
    await make().complete(DateTime(2026, 10, 21));
    expect(movements.saved, isEmpty);
    expect(settings.read().onboardingDone, isTrue);
  });

  test('conserva un walletStartedAt previo y los cobros borrados', () async {
    settings.value = WalletSettings(walletStartedAt: DateTime(2026, 9, 1), deletedChargeIds: const {'x'});
    await make(short: true).complete(DateTime(2026, 10, 21));
    expect(settings.read().walletStartedAt, DateTime(2026, 9, 1));
    expect(settings.read().deletedChargeIds, {'x'});
  });
}
