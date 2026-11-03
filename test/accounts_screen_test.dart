import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/friends/data/social_repository.dart';
import 'package:outflow/features/friends/presentation/friends_providers.dart';
import 'package:outflow/features/subscriptions/presentation/subscription_providers.dart';
import 'package:outflow/features/wallet/domain/account_balances.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/month_summary.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/screens/accounts_screen.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';
import 'package:outflow/features/wallet/presentation/widgets/transfer_sheet.dart';

import 'support/fakes.dart';

final now = DateTime(2026, 10, 20, 10, 30);

WalletAccount acc(
  String id, {
  String? name,
  bool isDefault = false,
  String currency = 'PEN',
  int initial = 0,
  bool archived = false,
  AccountType type = AccountType.bank,
}) =>
    WalletAccount(
      id: id,
      name: name ?? id.toUpperCase(),
      type: type,
      currency: currency,
      initialMinor: initial,
      initialDate: kAccountBeginning,
      isDefault: isDefault,
      archived: archived,
    );

Movement mv(String id, MovementKind kind, int minor, {String? accountId}) => Movement(
      id: id,
      kind: kind,
      amount: Money(minor, 'PEN'),
      categoryId: kind == MovementKind.income ? 'salary' : 'food',
      date: DateTime(2026, 10, 5),
      createdAt: DateTime(2026, 10, 5),
      accountId: accountId,
    );

class Env {
  Env(this.movements, this.accounts, this.container);
  final MemoryMovements movements;
  final MemoryAccounts accounts;
  final ProviderContainer container;
}

Env makeEnv(List<WalletAccount> initial, List<Movement> existing) {
  final movements = MemoryMovements(existing);
  final accounts = MemoryAccounts(initial, movements);
  final container = ProviderContainer(overrides: [
    nowProvider.overrideWithValue(now),
    movementRepositoryProvider.overrideWithValue(movements),
    accountRepositoryProvider.overrideWithValue(accounts),
    walletSettingsRepositoryProvider
        .overrideWithValue(MemorySettings(WalletSettings(onboardingDone: true, walletStartedAt: DateTime(2026, 10, 1)))),
    socialRepositoryProvider.overrideWithValue(const UnavailableSocialRepository()),
    categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
    subscriptionsProvider.overrideWith((ref) => Stream.value(const [])),
  ]);
  return Env(movements, accounts, container);
}

/// Un teléfono de 360 px de ancho.
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<Env> pumpScreen(
  WidgetTester tester, {
  List<WalletAccount>? accounts,
  List<Movement> movements = const [],
  Widget home = const AccountsScreen(),
}) async {
  phone(tester);
  final env = makeEnv(accounts ?? [acc('default', name: 'Mi cuenta', isDefault: true)], movements);
  addTearDown(env.container.dispose);
  // Como en la app, cuentas y movimientos ya están cargados y escuchados.
  env.container.listen(accountsProvider, (_, _) {});
  env.container.listen(movementsProvider, (_, _) {});
  await tester.pumpWidget(UncontrolledProviderScope(
    container: env.container,
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
  return env;
}

Future<void> tapDigits(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.text(d));
  }
  await tester.pump();
}

void main() {
  group('lista y editor', () {
    testWidgets('crear una cuenta con su saldo y verla en la lista', (tester) async {
      final env = await pumpScreen(tester);
      await tester.tap(find.bySemanticsLabel('Nueva cuenta'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'BCP');
      await tapDigits(tester, '150');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final created = env.accounts.saved.firstWhere((a) => a.name == 'BCP');
      expect(created.initialMinor, 15000);
      expect(created.initialDate, now, reason: 'el saldo tecleado es el de este instante');
      expect(created.currency, 'PEN');
      expect(created.isDefault, isFalse);
      expect(env.accounts.saved, hasLength(2));
      expect(find.text('BCP'), findsOneWidget);
      expect(find.textContaining('150.00'), findsWidgets);
    });

    testWidgets('las sugerencias rellenan el nombre', (tester) async {
      final env = await pumpScreen(tester);
      await tester.tap(find.bySemanticsLabel('Nueva cuenta'));
      await tester.pumpAndSettle();
      for (final s in ['BCP', 'BBVA', 'Interbank', 'Scotiabank', 'Dale', 'Yape', 'Plin', 'Efectivo']) {
        expect(find.text(s), findsWidgets, reason: s);
      }
      await tester.tap(find.text('Yape'));
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(env.accounts.saved.map((a) => a.name), contains('Yape'));
    });

    testWidgets('sin nombre no se puede guardar', (tester) async {
      final env = await pumpScreen(tester);
      await tester.tap(find.bySemanticsLabel('Nueva cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(env.accounts.saved, hasLength(1));
    });

    testWidgets('las archivadas salen aparte y no suman en el total', (tester) async {
      await pumpScreen(tester, accounts: [
        acc('default', name: 'Mi cuenta', isDefault: true, initial: 10000),
        acc('old', name: 'Vieja', initial: 99900, archived: true),
      ]);
      expect(find.text('Archivadas'), findsOneWidget);
      expect(find.text('Vieja'), findsOneWidget);
      expect(find.textContaining('1,099'), findsNothing, reason: 'el total no incluye la archivada');
      expect(find.textContaining('999.00'), findsOneWidget, reason: 'solo el saldo de la propia fila');
    });

    testWidgets('a 360 px una lista con nombres y saldos enormes no desborda', (tester) async {
      await pumpScreen(tester, accounts: [
        acc('default', name: 'Mi cuenta con un nombre larguísimo de verdad', isDefault: true, initial: 123456789),
        acc('b', name: 'Tarjeta de crédito del banco con nombre enorme', initial: -98765432, type: AccountType.creditCard),
        acc('c', currency: 'USD', initial: 5000),
      ]);
      expect(tester.takeException(), isNull);
    });
  });

  group('detalle', () {
    testWidgets('"Mi saldo real es…" crea un ajuste y el saldo queda en ese valor; "Te queda" no cambia', (tester) async {
      final env = await pumpScreen(
        tester,
        accounts: [acc('default', name: 'BCP', isDefault: true)],
        movements: [mv('a', MovementKind.income, 10000), mv('b', MovementKind.expense, 1000)],
      );
      final month = monthOf(now);
      env.container.listen(monthSummaryProvider(month), (_, _) {});
      await tester.pumpAndSettle();
      final before = env.container.read(monthSummaryProvider(month)).value!.remaining;

      await tester.tap(find.text('BCP'));
      await tester.pumpAndSettle();
      expect(find.textContaining('90.00'), findsWidgets);
      await tester.tap(find.text('Mi saldo real es…'));
      await tester.pumpAndSettle();
      await tapDigits(tester, '80');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final adj = env.movements.saved.singleWhere((m) => m.kind == MovementKind.adjustment);
      expect(adj.adjustmentMinor, -1000);
      expect(adj.accountId, 'default');
      expect(adj.title, 'Ajuste de saldo');
      expect(computeBalances(env.accounts.saved, env.movements.saved)['default'], 8000);
      expect(env.container.read(monthSummaryProvider(month)).value!.remaining, before);
      expect(find.textContaining('80.00'), findsWidgets);
    });

    testWidgets('ajustar al mismo saldo no crea nada', (tester) async {
      final env = await pumpScreen(
        tester,
        accounts: [acc('default', name: 'BCP', isDefault: true, initial: 5000)],
      );
      await tester.tap(find.text('BCP'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mi saldo real es…'));
      await tester.pumpAndSettle();
      await tapDigits(tester, '50');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(env.movements.saved, isEmpty);
    });

    testWidgets('"Usar como cuenta por defecto" no mueve ningún saldo', (tester) async {
      final env = await pumpScreen(
        tester,
        accounts: [acc('default', name: 'BCP', isDefault: true), acc('bbva', name: 'BBVA')],
        movements: [mv('a', MovementKind.income, 10000)],
      );
      final before = computeBalances(env.accounts.saved, env.movements.saved);
      await tester.tap(find.text('BBVA'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Usar como cuenta por defecto'));
      await tester.tap(find.text('Usar como cuenta por defecto'));
      await tester.pumpAndSettle();
      expect(env.accounts.saved.where((a) => a.isDefault).map((a) => a.id), ['bbva']);
      expect(computeBalances(env.accounts.saved, env.movements.saved), before);
    });

    testWidgets('una cuenta con movimientos se archiva; la por defecto no se ofrece', (tester) async {
      final env = await pumpScreen(
        tester,
        accounts: [acc('default', name: 'BCP', isDefault: true), acc('bbva', name: 'BBVA')],
        movements: [mv('c', MovementKind.expense, 500, accountId: 'bbva')],
      );
      await tester.tap(find.text('BCP'));
      await tester.pumpAndSettle();
      expect(find.text('Archivar cuenta'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Atrás'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('BBVA'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Archivar cuenta'));
      await tester.tap(find.text('Archivar cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archivar').last);
      await tester.pumpAndSettle();
      expect(env.accounts.saved.firstWhere((a) => a.id == 'bbva').archived, isTrue);
    });
  });

  group('transferencias', () {
    Future<void> openTransfer(WidgetTester tester) async {
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    Widget opener() => Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showTransferSheet(context), child: const Text('abrir')),
          ),
        );

    testWidgets('con una sola cuenta pide crear otra', (tester) async {
      final env = await pumpScreen(tester, home: opener());
      await openTransfer(tester);
      expect(find.text('Necesitas otra cuenta'), findsOneWidget);
      await tester.tap(find.text('Crear cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Efectivo');
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(env.accounts.saved.map((a) => a.name), contains('Efectivo'));
    });

    testWidgets('una cuenta archivada no cuenta: sigue pidiendo otra', (tester) async {
      await pumpScreen(tester, home: opener(), accounts: [
        acc('default', name: 'BCP', isDefault: true),
        acc('old', archived: true),
      ]);
      await openTransfer(tester);
      expect(find.text('Necesitas otra cuenta'), findsOneWidget);
    });

    testWidgets('transferir mueve el saldo de ambas cuentas y conserva la hora de hoy', (tester) async {
      final env = await pumpScreen(tester, home: opener(), accounts: [
        acc('default', name: 'BCP', isDefault: true, initial: 10000),
        acc('dale', name: 'Dale'),
        acc('efe', name: 'Efectivo'),
      ]);
      await openTransfer(tester);
      expect(find.text('Transferencia'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('transfer-to')), matching: find.text('Efectivo')));
      await tester.pump();
      await tapDigits(tester, '25');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final t = env.movements.saved.single;
      expect(t.kind, MovementKind.transfer);
      expect(t.accountId, 'default');
      expect(t.toAccountId, 'efe');
      expect(t.amount, const Money(2500, 'PEN'));
      expect(t.date, now, reason: 'hoy conserva la hora');
      expect(t.createdAt, now);
      expect(computeBalances(env.accounts.saved, env.movements.saved), {'default': 7500, 'dale': 0, 'efe': 2500});
    });

    testWidgets('entre monedas pide lo que recibe la otra cuenta', (tester) async {
      final env = await pumpScreen(tester, home: opener(), accounts: [
        acc('default', name: 'BCP', isDefault: true, initial: 100000),
        acc('usd', name: 'Dólares', currency: 'USD'),
      ]);
      await openTransfer(tester);
      expect(find.text('Recibe'), findsOneWidget);
      await tapDigits(tester, '370');
      await tester.tap(find.text('Recibe'));
      await tester.pump();
      await tapDigits(tester, '100');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      final t = env.movements.saved.single;
      expect(t.amount, const Money(37000, 'PEN'));
      expect(t.receivedMinor, 10000);
      expect(computeBalances(env.accounts.saved, env.movements.saved), {'default': 63000, 'usd': 10000});
    });

    testWidgets('no deja guardar sin importe y a 360 px no desborda', (tester) async {
      final env = await pumpScreen(tester, home: opener(), accounts: [
        acc('default', name: 'BCP', isDefault: true),
        acc('b', name: 'Cuenta con un nombre larguísimo de verdad'),
      ]);
      await openTransfer(tester);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(env.movements.saved, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
