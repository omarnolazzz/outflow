import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/wallet/domain/category.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';
import 'package:outflow/features/wallet/presentation/widgets/movement_sheet.dart';

import 'support/fakes.dart';

void main() {
  final now = DateTime(2026, 10, 20, 10, 30);

  group('WalletActions', () {
    test('borrar un gasto de suscripción lo recuerda; deshacer lo restaura y lo olvida', () async {
      final m = Movement(
        id: 'sub:nf:2026-10-18',
        kind: MovementKind.expense,
        amount: const Money(2990, 'PEN'),
        categoryId: kSubscriptionsCategoryId,
        date: DateTime(2026, 10, 18),
        createdAt: DateTime(2026, 10, 18),
        origin: MovementOrigin.subscription,
        subscriptionId: 'nf',
        provisional: true,
      );
      final movements = MemoryMovements([m]);
      final settings = MemorySettings();
      final actions = WalletActions(movements, settings);

      final deleted = await actions.delete(m.id);
      expect(deleted?.id, m.id);
      expect(movements.saved, isEmpty);
      expect(settings.read().deletedChargeIds, {m.id});

      await actions.restore(deleted!);
      expect(movements.saved.single.id, m.id);
      expect(settings.read().deletedChargeIds, isEmpty);
    });

    test('borrar un gasto manual no toca los cobros borrados', () async {
      final m = Movement(
        id: 'x',
        kind: MovementKind.expense,
        amount: const Money(100, 'PEN'),
        categoryId: 'food',
        date: now,
        createdAt: now,
      );
      final settings = MemorySettings();
      await WalletActions(MemoryMovements([m]), settings).delete('x');
      expect(settings.read().deletedChargeIds, isEmpty);
    });
  });

  testWidgets('registrar un gasto en 3 toques: importe → categoría → Guardar', (tester) async {
    final movements = MemoryMovements();
    final settings = MemorySettings(const WalletSettings());
    final container = ProviderContainer(overrides: [
      nowProvider.overrideWithValue(now),
      movementRepositoryProvider.overrideWithValue(movements),
      walletSettingsRepositoryProvider.overrideWithValue(settings),
      categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showMovementSheet(context, kind: MovementKind.expense),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('5'));
    await tester.tap(find.text('0'));
    await tester.pump();
    await tester.tap(find.text('Transporte'));
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final m = movements.saved.single;
    expect(m.kind, MovementKind.expense);
    expect(m.amount, const Money(5000, 'PEN'));
    expect(m.categoryId, 'transport');
    expect(m.origin, MovementOrigin.manual);
    expect(DateUtils.dateOnly(m.date), DateTime(2026, 10, 20));
    expect(find.text('Guardar'), findsNothing, reason: 'la hoja se cierra');
  });

  testWidgets('la categoría reservada de suscripciones no se ofrece al registrar a mano', (tester) async {
    final container = ProviderContainer(overrides: [
      nowProvider.overrideWithValue(now),
      movementRepositoryProvider.overrideWithValue(MemoryMovements()),
      walletSettingsRepositoryProvider.overrideWithValue(MemorySettings()),
      categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMovementSheet(context, kind: MovementKind.expense),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Suscripciones'), findsNothing);
    expect(find.text('Comida'), findsOneWidget);
  });
}
