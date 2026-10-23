import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/subscriptions/presentation/subscription_providers.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/screens/movements_screen.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';

void main() {
  final now = DateTime(2026, 10, 20, 10);

  testWidgets('un gasto compartido no se puede deslizar para borrar', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final split = Movement(
      id: 'split:e1',
      kind: MovementKind.expense,
      amount: const Money(3333, 'PEN'),
      categoryId: 'food',
      date: now,
      createdAt: now,
      title: 'Cena compartida',
      origin: MovementOrigin.split,
    );
    final repo = MemoryMovements([split]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nowProvider.overrideWithValue(now),
        movementRepositoryProvider.overrideWithValue(repo),
        subscriptionsProvider.overrideWith((ref) => Stream.value(const [])),
        walletSettingsRepositoryProvider.overrideWithValue(MemorySettings(WalletSettings(walletStartedAt: DateTime(2026, 5, 1)))),
        categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
      ],
      child: const MaterialApp(home: MovementsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Cena compartida'), findsOneWidget);
    await tester.drag(find.text('Cena compartida'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Cena compartida'), findsOneWidget);
    expect(repo.saved.single.id, 'split:e1');
  });
}
