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

    test('dropCharge borra el gasto del cobro y lo recuerda; deshacer lo devuelve', () async {
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
      final dropped = await actions.dropCharge('nf', DateTime(2026, 10, 18));
      expect(movements.saved, isEmpty);
      expect(settings.read().deletedChargeIds, {m.id});
      await actions.restore(dropped!);
      expect(movements.saved.single.id, m.id);
    });

    test('un gasto compartido (split) no se borra', () async {
      final m = Movement(
        id: 'split:e1',
        kind: MovementKind.expense,
        amount: const Money(3333, 'PEN'),
        categoryId: 'food',
        date: now,
        createdAt: now,
        origin: MovementOrigin.split,
      );
      final movements = MemoryMovements([m]);
      expect(await WalletActions(movements, MemorySettings()).delete(m.id), isNull);
      expect(movements.saved.single.id, m.id);
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

  testWidgets('un gasto compartido solo deja editar categoría y nota', (tester) async {
    final split = Movement(
      id: 'split:e1',
      kind: MovementKind.expense,
      amount: const Money(3333, 'PEN'),
      categoryId: 'food',
      date: now,
      createdAt: now,
      title: 'Cena',
      origin: MovementOrigin.split,
    );
    final movements = MemoryMovements([split]);
    final container = ProviderContainer(overrides: [
      nowProvider.overrideWithValue(now),
      movementRepositoryProvider.overrideWithValue(movements),
      walletSettingsRepositoryProvider.overrideWithValue(MemorySettings()),
      categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMovementSheet(context, editing: split),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Gasto compartido · se edita en Amigos'), findsOneWidget);
    expect(find.bySemanticsLabel('Borrar'), findsNothing);
    expect(find.text('Comida'), findsOneWidget, reason: 'la categoría sí se edita');
    expect(find.text('7'), findsNothing, reason: 'sin teclado de importe');

    await tester.tap(find.text('Transporte'));
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final saved = movements.saved.single;
    expect(saved.categoryId, 'transport');
    expect(saved.amount, const Money(3333, 'PEN'));
    expect(saved.title, 'Cena');
  });
}
