import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/wallet/domain/account_balances.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';

WalletAccount acc(String id, {bool isDefault = false, String currency = 'PEN', int initial = 0, bool archived = false}) =>
    WalletAccount(
      id: id,
      name: id.toUpperCase(),
      type: AccountType.bank,
      currency: currency,
      initialMinor: initial,
      initialDate: kAccountBeginning,
      isDefault: isDefault,
      archived: archived,
    );

Movement mv(String id, MovementKind kind, int minor, {String? accountId, String currency = 'PEN'}) => Movement(
      id: id,
      kind: kind,
      amount: Money(minor, currency),
      categoryId: 'food',
      date: DateTime(2026, 10, 5),
      createdAt: DateTime(2026, 10, 5),
      accountId: accountId,
    );

void main() {
  group('setDefault', () {
    test('sella el historial sin cuenta con la cuenta anterior: ningún saldo cambia', () async {
      final movements = MemoryMovements([
        mv('a', MovementKind.income, 10000),
        mv('b', MovementKind.expense, 2500),
        mv('c', MovementKind.expense, 1000, accountId: 'bbva'),
      ]);
      final accounts = MemoryAccounts([acc('default', isDefault: true), acc('bbva')], movements);
      final before = computeBalances(accounts.saved, movements.saved);
      expect(before, {'default': 7500, 'bbva': -1000});

      await AccountActions(accounts, movements).setDefault('bbva');

      expect(accounts.saved.where((a) => a.isDefault).map((a) => a.id), ['bbva']);
      expect(movements.saved.every((m) => m.accountId != null), isTrue);
      expect(computeBalances(accounts.saved, movements.saved), before);
    });

    test('es idempotente y no hace nada con una cuenta desconocida o archivada', () async {
      final movements = MemoryMovements([mv('a', MovementKind.income, 100)]);
      final accounts = MemoryAccounts([acc('default', isDefault: true), acc('old', archived: true)], movements);
      final actions = AccountActions(accounts, movements);
      await actions.setDefault('default');
      await actions.setDefault('nope');
      await actions.setDefault('old');
      expect(accounts.saved.where((a) => a.isDefault).map((a) => a.id), ['default']);
      expect(movements.saved.single.accountId, isNull);
    });
  });

  group('cambio de moneda de una cuenta', () {
    test('solo si no tiene movimientos, contando los que no indican cuenta en la por defecto', () async {
      final movements = MemoryMovements([mv('a', MovementKind.income, 100)]);
      final accounts = MemoryAccounts([acc('default', isDefault: true), acc('bbva')], movements);
      final actions = AccountActions(accounts, movements);

      expect(await actions.hasMovements('default'), isTrue);
      expect(await actions.setCurrencyIfUnused('default', 'USD'), isFalse);
      expect(accounts.saved.firstWhere((a) => a.id == 'default').currency, 'PEN');

      expect(await actions.hasMovements('bbva'), isFalse);
      expect(await actions.setCurrencyIfUnused('bbva', 'USD'), isTrue);
      expect(accounts.saved.firstWhere((a) => a.id == 'bbva').currency, 'USD');
    });
  });
}
