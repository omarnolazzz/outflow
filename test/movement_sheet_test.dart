import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/friends/data/social_repository.dart';
import 'package:outflow/features/friends/presentation/friends_providers.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/wallet/domain/category.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/account_balances.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
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
      socialRepositoryProvider.overrideWithValue(const UnavailableSocialRepository()),
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
      socialRepositoryProvider.overrideWithValue(const UnavailableSocialRepository()),
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
      socialRepositoryProvider.overrideWithValue(const UnavailableSocialRepository()),
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

  group('cuenta del gasto', () {
    WalletAccount account(String id, String name, {bool isDefault = false, String currency = 'PEN', bool archived = false}) =>
        WalletAccount(
          id: id,
          name: name,
          type: AccountType.bank,
          currency: currency,
          initialMinor: 10000,
          initialDate: kAccountBeginning,
          isDefault: isDefault,
          archived: archived,
        );

    Future<(MemoryMovements, MemoryAccounts)> open(
      WidgetTester tester,
      List<WalletAccount> accounts, {
      Movement? editing,
      List<Movement> existing = const [],
    }) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final movements = MemoryMovements([...existing, ?editing]);
      final repo = MemoryAccounts(accounts, movements);
      final container = ProviderContainer(overrides: [
        nowProvider.overrideWithValue(now),
        movementRepositoryProvider.overrideWithValue(movements),
        accountRepositoryProvider.overrideWithValue(repo),
        socialRepositoryProvider.overrideWithValue(const UnavailableSocialRepository()),
        walletSettingsRepositoryProvider.overrideWithValue(MemorySettings(const WalletSettings())),
        categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
      ]);
      addTearDown(container.dispose);
      container.listen(accountsProvider, (_, _) {});
      container.listen(movementsProvider, (_, _) {});
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMovementSheet(context, editing: editing),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      return (movements, repo);
    }

    final two = [account('default', 'BCP', isDefault: true), account('bbva', 'BBVA')];

    testWidgets('un gasto con la cuenta elegida baja esa cuenta y no la otra', (tester) async {
      final (movements, repo) = await open(tester, two);
      expect(find.text('Cuenta'), findsOneWidget);
      await tester.tap(find.text('BBVA'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.tap(find.text('0'));
      await tester.pump();
      await tester.tap(find.text('Transporte'));
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final m = movements.saved.single;
      expect(m.accountId, 'bbva');
      expect(computeBalances(repo.saved, movements.saved), {'default': 10000, 'bbva': 7000});
    });

    testWidgets('empieza en la cuenta por defecto y la guarda explícita', (tester) async {
      final (movements, repo) = await open(tester, two);
      await tester.tap(find.text('8'));
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(movements.saved.single.accountId, 'default');
      expect(computeBalances(repo.saved, movements.saved), {'default': 9200, 'bbva': 10000});
    });

    testWidgets('con una sola cuenta (o las demás archivadas) no se muestra el selector', (tester) async {
      final (movements, _) = await open(tester, [
        account('default', 'BCP', isDefault: true),
        account('old', 'Vieja', archived: true),
      ]);
      expect(find.text('Cuenta'), findsNothing);
      expect(find.text('Vieja'), findsNothing);
      await tester.tap(find.text('8'));
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(movements.saved.single.accountId, isNull);
    });

    testWidgets('el gasto toma la moneda de la cuenta elegida', (tester) async {
      final (movements, _) = await open(tester, [...two, account('usd', 'Dólares', currency: 'USD')]);
      await tester.ensureVisible(find.text('Dólares'));
      await tester.pump();
      await tester.tap(find.text('Dólares'));
      await tester.pump();
      await tester.tap(find.text('9'));
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(movements.saved.single.amount, const Money(900, 'USD'));
      expect(movements.saved.single.accountId, 'usd');
    });

    testWidgets('editar un cobro de suscripción no muestra el selector', (tester) async {
      final charge = Movement(
        id: 'sub:nf:2026-10-18',
        kind: MovementKind.expense,
        amount: const Money(2990, 'PEN'),
        categoryId: kSubscriptionsCategoryId,
        date: DateTime(2026, 10, 18),
        createdAt: DateTime(2026, 10, 18),
        origin: MovementOrigin.subscription,
        subscriptionId: 'nf',
      );
      await open(tester, two, editing: charge);
      expect(find.text('Cuenta'), findsNothing);
    });

    testWidgets('editar un gasto muestra su cuenta y permite cambiarla', (tester) async {
      final lunch = Movement(
        id: 'x',
        kind: MovementKind.expense,
        amount: const Money(1500, 'PEN'),
        categoryId: 'food',
        date: now,
        createdAt: now,
        accountId: 'bbva',
      );
      final (movements, _) = await open(tester, two, editing: lunch);
      await tester.tap(find.text('BCP'));
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(movements.saved.single.accountId, 'default');
    });

    testWidgets('a 360 px con varias cuentas de nombre largo no desborda', (tester) async {
      await open(tester, [
        account('default', 'Cuenta sueldo con un nombre larguísimo', isDefault: true),
        account('b', 'Otra cuenta con un nombre aún más largo'),
        account('c', 'Tercera'),
      ]);
      expect(tester.takeException(), isNull);
    });
  });
}
