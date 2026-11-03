import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/onboarding/presentation/onboarding_controller.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';

import 'support/fakes.dart';

void main() {
  late MemorySettings settings;
  late MemoryMovements movements;
  late MemoryAccounts accounts;

  setUp(() {
    settings = MemorySettings();
    movements = MemoryMovements();
    accounts = MemoryAccounts();
  });

  OnboardingController make({bool short = false}) =>
      OnboardingController(short: short, settings: settings, movements: movements, accounts: accounts);

  test('el flujo completo tiene 7 pasos y el corto 4 (sin "Tu primera cuenta")', () {
    expect(make().steps, [
      OnboardingStep.currency,
      OnboardingStep.firstAccount,
      OnboardingStep.carryOver,
      OnboardingStep.subscriptions,
      OnboardingStep.notifications,
      OnboardingStep.faceId,
      OnboardingStep.done,
    ]);
    expect(make(short: true).steps, [
      OnboardingStep.currency,
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
    expect(c.accountName, 'Mi cuenta');
    expect(c.faceId, isFalse);
  });

  test('complete reescribe "Mi cuenta": nombre, moneda y saldo desde ahora, sin movimiento "Saldo inicial"', () async {
    final now = DateTime(2026, 10, 21, 9);
    // Como tras borrar todo: la cuenta por defecto ya existe, en otra moneda.
    await accounts.ensureDefault('PEN');
    final c = make()
      ..setCurrency('USD')
      ..setAccountName('  BBVA ')
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

    final a = accounts.saved.single;
    expect(a.id, kDefaultAccountId);
    expect(a.isDefault, isTrue);
    expect(a.name, 'BBVA');
    expect(a.currency, 'USD');
    expect(a.initialMinor, 150000);
    expect(a.initialDate, now);
    expect(movements.saved.where((m) => m.origin == MovementOrigin.initialBalance), isEmpty);
    expect(movements.saved, isEmpty);
  });

  test('sin cuenta previa la crea una sola vez; sin nombre queda "Mi cuenta"', () async {
    await (make()..setAccountName('   ')).complete(DateTime(2026, 10, 21));
    final a = accounts.saved.single;
    expect(a.name, 'Mi cuenta');
    expect(a.initialMinor, 0);
    expect(movements.saved, isEmpty);
    expect(settings.read().onboardingDone, isTrue);
  });

  test('el flujo corto no toca las cuentas de quien ya tenía datos', () async {
    final existing = newDefaultAccount('PEN');
    accounts = MemoryAccounts([existing]);
    await make(short: true).complete(DateTime(2026, 10, 21));
    expect(accounts.saved.single.toJson(), existing.toJson());
  });

  test('conserva un walletStartedAt previo y los cobros borrados', () async {
    settings.value = WalletSettings(walletStartedAt: DateTime(2026, 9, 1), deletedChargeIds: const {'x'});
    await make(short: true).complete(DateTime(2026, 10, 21));
    expect(settings.read().walletStartedAt, DateTime(2026, 9, 1));
    expect(settings.read().deletedChargeIds, {'x'});
  });
}
