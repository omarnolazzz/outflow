import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/friends/domain/shared_expense.dart';
import 'package:outflow/features/friends/presentation/friends_providers.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';

const me = Person(uid: 'u', name: 'Gabriel Nolazco', email: 'g@example.com');
const ana = Person(uid: 'ana', name: 'Ana Pérez', email: 'ana@x.com');
const eve = Person(uid: 'eve', name: 'Eve', email: 'eve@x.com');

SharedExpense owed(String id, {required Person by}) => SharedExpense(
      id: id,
      createdBy: by.uid,
      paidBy: by.uid,
      participants: [me.uid, by.uid],
      people: {me.uid: me, by.uid: by},
      title: 'Cena',
      date: DateTime(2026, 10, 19),
      currency: 'PEN',
      totalMinor: 10000,
      categoryId: 'food',
      mode: SplitMode.equal,
      shares: {me.uid: 5000, by.uid: 5000},
      updatedAt: DateTime(2026, 10, 19),
    );

void main() {
  // Alguien que conoce tu uid puede crear un gasto contigo sin ser tu amigo:
  // no debe tocar tu wallet ni tus saldos.
  test('solo cuentan los gastos creados por ti o por un amigo', () async {
    final movements = MemoryMovements();
    final container = ProviderContainer(overrides: [
      socialRepositoryProvider.overrideWithValue(
        MemorySocial(friends: [ana], expenses: [owed('e-ana', by: ana), owed('e-eve', by: eve)]),
      ),
      movementRepositoryProvider.overrideWithValue(movements),
      walletSettingsRepositoryProvider.overrideWithValue(MemorySettings()),
      categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
      currentAccountProvider.overrideWithValue(
        const Account(uid: 'u', email: 'g@example.com', displayName: 'Gabriel Nolazco'),
      ),
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(splitMovementSyncProvider, (_, _) {});
    addTearDown(sub.close);
    container.listen(balancesProvider, (_, _) {});

    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(container.read(balancesProvider).map((b) => b.friendUid), ['ana']);
    expect(movements.saved.map((m) => m.id), ['split:e-ana']);
  });
}
