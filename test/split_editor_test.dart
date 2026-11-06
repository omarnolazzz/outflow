import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/core/widgets/primary_button.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/friends/domain/shared_expense.dart';
import 'package:outflow/features/friends/presentation/friends_providers.dart';
import 'package:outflow/features/friends/presentation/split_editor_screen.dart';
import 'package:outflow/features/receipts/domain/receipt.dart';
import 'package:outflow/features/wallet/domain/apple_pay_link.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';
import 'package:outflow/features/wallet/presentation/widgets/movement_sheet.dart';

import 'support/fakes.dart';

const me = Person(uid: 'u', name: 'Gabriel Nolazco', email: 'g@example.com');
const ana = Person(uid: 'ana', name: 'Ana Pérez', email: 'ana@x.com');

/// Un servidor que nunca confirma: así se comporta Firestore sin red.
class HangingSocial extends MemorySocial {
  HangingSocial({super.friends});
  final saves = <SharedExpense>[];

  @override
  Future<void> saveExpense(SharedExpense e) {
    saves.add(e);
    return Completer<void>().future;
  }
}

class FailingSocial extends MemorySocial {
  FailingSocial({super.friends});

  @override
  Future<void> saveExpense(SharedExpense e) => Future<void>.error(StateError('sin permiso'));
}

void main() {
  final now = DateTime(2026, 10, 20, 19);
  final draft = SplitDraft(
    totalMinor: 10000,
    currency: 'PEN',
    title: 'Cena',
    date: now,
    categoryId: 'food',
  );

  Future<MemoryMovements> pump(
    WidgetTester tester,
    MemorySocial social, {
    SplitDraft? draft,
    SharedExpense? editing,
    List<Movement> existing = const [],
    Widget? home,
    List<WalletAccount> accounts = const [],
    MemorySettings? settings,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final movements = MemoryMovements(existing);
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        nowProvider.overrideWithValue(now),
        socialRepositoryProvider.overrideWithValue(social),
        movementRepositoryProvider.overrideWithValue(movements),
        walletSettingsRepositoryProvider.overrideWithValue(settings ?? MemorySettings(const WalletSettings())),
        if (accounts.isNotEmpty) accountRepositoryProvider.overrideWithValue(MemoryAccounts(accounts, movements)),
        categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
        currentAccountProvider.overrideWithValue(
          const Account(uid: 'u', email: 'g@example.com', displayName: 'Gabriel Nolazco'),
        ),
      ],
      child: MaterialApp(
        home: home ??
            Scaffold(body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSplitEditor(context, draft: draft, editing: editing),
                child: const Text('abrir'),
              ),
            )),
      ),
    ));
    await tester.pumpAndSettle();
    if (home == null) {
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }
    return movements;
  }

  Movement googlePay({String id = 'gp'}) => Movement(
        id: id,
        kind: MovementKind.expense,
        amount: const Money(10000, 'PEN'),
        categoryId: 'food',
        date: now.subtract(const Duration(hours: 1)),
        createdAt: now.subtract(const Duration(hours: 1)),
        title: 'Restaurante',
        origin: MovementOrigin.googlePay,
      );

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<PrimaryButton>(find.widgetWithText(PrimaryButton, 'Guardar')).onTap != null;

  testWidgets('100 entre tú y Ana a partes iguales: guarda 50/50 pagado por ti', (tester) async {
    final social = MemorySocial(friends: [ana]);
    await pump(tester, social, draft: draft);
    expect(saveEnabled(tester), isFalse, reason: 'solo tú: faltan participantes');
    await tapKey(tester, 'with-ana');
    expect(find.text('Tu parte: S/50.00'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final e = social.expenses.single;
    expect(e.shares, {'u': 5000, 'ana': 5000});
    expect(e.paidBy, 'u');
    expect(e.createdBy, 'u');
    expect(e.participants, ['u', 'ana']);
    expect(e.people.keys, containsAll(['u', 'ana']));
    expect(e.mode, SplitMode.equal);
    expect(e.title, 'Cena');
    expect(e.totalMinor, 10000);
    expect(find.byType(SplitEditorScreen), findsNothing);
  });

  testWidgets('modo Importes: 60 y 30 sobre 100 deja Guardar deshabilitado y avisa', (tester) async {
    final social = MemorySocial(friends: [ana]);
    await pump(tester, social, draft: draft);
    await tapKey(tester, 'with-ana');
    await tester.tap(find.text('Importes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('amount-u')), '60');
    await tester.enterText(find.byKey(const ValueKey('amount-ana')), '30');
    await tester.pumpAndSettle();
    expect(find.textContaining('Faltan S/10.00'), findsOneWidget);
    expect(saveEnabled(tester), isFalse);
    await tester.enterText(find.byKey(const ValueKey('amount-ana')), '40');
    await tester.pumpAndSettle();
    expect(saveEnabled(tester), isTrue);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(social.expenses.single.shares, {'u': 6000, 'ana': 4000});
    expect(social.expenses.single.mode, SplitMode.amounts);
  });

  testWidgets('modo Productos: reparte según las personas de cada producto', (tester) async {
    final social = MemorySocial(friends: [ana]);
    final ticket = SplitDraft(
      totalMinor: 1550,
      currency: 'PEN',
      title: 'Bodega',
      date: now,
      categoryId: 'food',
      items: const [
        ReceiptItem(name: 'Gaseosa', amountMinor: 700),
        ReceiptItem(name: 'Pan', amountMinor: 850),
      ],
    );
    await pump(tester, social, draft: ticket);
    await tapKey(tester, 'with-ana');
    await tester.tap(find.text('Productos'));
    await tester.pumpAndSettle();
    // La gaseosa es solo de Ana; el pan, de los dos.
    await tapKey(tester, 'item-0-u');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final e = social.expenses.single;
    expect(e.mode, SplitMode.items);
    expect(e.shares, {'u': 425, 'ana': 1125});
    expect(e.items.map((i) => i.uids), [
      ['ana'],
      ['u', 'ana'],
    ]);
  });

  testWidgets('sin productos no hay modo Productos', (tester) async {
    await pump(tester, MemorySocial(friends: [ana]), draft: draft);
    expect(find.text('Iguales'), findsOneWidget);
    expect(find.text('Importes'), findsOneWidget);
    expect(find.text('Productos'), findsNothing);
  });

  testWidgets('un pago de Google Pay parecido: elegirlo lo borra de la wallet y guarda el compartido', (tester) async {
    final social = MemorySocial(friends: [ana]);
    final movements = await pump(tester, social, draft: draft, existing: [googlePay()]);
    await tapKey(tester, 'with-ana');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Es este pago?'), findsOneWidget);
    await tester.tap(find.text('Restaurante'));
    await tester.pumpAndSettle();
    expect(movements.saved, isEmpty);
    expect(social.expenses, hasLength(1));
    expect(find.byType(SplitEditorScreen), findsNothing);
  });

  testWidgets('"No, es otro" guarda el compartido sin borrar nada', (tester) async {
    final social = MemorySocial(friends: [ana]);
    final movements = await pump(tester, social, draft: draft, existing: [googlePay()]);
    await tapKey(tester, 'with-ana');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, es otro'));
    await tester.pumpAndSettle();
    expect(movements.saved.single.id, 'gp');
    expect(social.expenses, hasLength(1));
  });

  testWidgets('tu parte ya registrada no se ofrece como pago', (tester) async {
    final social = MemorySocial(friends: [ana]);
    final g = googlePay();
    final share = Movement(
      id: 'sp',
      kind: g.kind,
      amount: g.amount,
      categoryId: g.categoryId,
      date: g.date,
      createdAt: g.createdAt,
      title: g.title,
      origin: MovementOrigin.split,
    );
    await pump(tester, social, draft: draft, existing: [share]);
    await tapKey(tester, 'with-ana');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Es este pago?'), findsNothing);
    expect(social.expenses, hasLength(1));
  });

  testWidgets('sin red el guardado nunca termina, pero el editor se cierra y el pago elegido se borra', (tester) async {
    final social = HangingSocial(friends: [ana]);
    final movements = await pump(tester, social, draft: draft, existing: [googlePay()]);
    await tapKey(tester, 'with-ana');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurante'));
    await tester.pumpAndSettle();
    expect(social.saves, hasLength(1));
    expect(find.byType(SplitEditorScreen), findsNothing);
    expect(movements.saved, isEmpty);
  });

  testWidgets('un error al guardar avisa con un SnackBar', (tester) async {
    final social = FailingSocial(friends: [ana]);
    await pump(tester, social, draft: draft);
    await tapKey(tester, 'with-ana');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.byType(SplitEditorScreen), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('quien pagó siempre participa', (tester) async {
    final social = MemorySocial(friends: [ana]);
    await pump(tester, social, draft: draft);
    await tapKey(tester, 'with-ana');
    await tapKey(tester, 'paid-ana');
    await tapKey(tester, 'with-ana'); // intenta quitar a quien pagó: se ignora
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(social.expenses.single.paidBy, 'ana');
    expect(social.expenses.single.participants, containsAll(['u', 'ana']));
  });

  testWidgets('tú siempre participas aunque pague otra persona', (tester) async {
    const bea = Person(uid: 'bea', name: 'Bea Ruiz', email: 'bea@x.com');
    final social = MemorySocial(friends: [ana, bea]);
    await pump(tester, social, draft: draft);
    await tapKey(tester, 'paid-ana');
    await tapKey(tester, 'with-u'); // intenta quitarte: se ignora
    await tapKey(tester, 'with-bea');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final e = social.expenses.single;
    expect(e.paidBy, 'ana');
    expect(e.participants, containsAll(['u', 'ana', 'bea']));
  });

  group('cuenta de la que salió', () {
    final bank = WalletAccount(
      id: 'A',
      name: 'Banco',
      type: AccountType.bank,
      currency: 'PEN',
      initialMinor: 0,
      initialDate: kAccountBeginning,
      isDefault: true,
    );
    final savings = WalletAccount(
      id: 'B',
      name: 'Ahorros',
      type: AccountType.bank,
      currency: 'PEN',
      initialMinor: 0,
      initialDate: kAccountBeginning,
    );

    testWidgets('si pagas tú, eliges la cuenta y se guarda local para ese gasto', (tester) async {
      final social = MemorySocial(friends: [ana]);
      final settings = MemorySettings(const WalletSettings());
      await pump(tester, social, draft: draft, accounts: [bank, savings], settings: settings);
      expect(find.text('¿De qué cuenta salió?'), findsOneWidget);
      await tapKey(tester, 'with-ana');
      await tester.tap(find.text('Ahorros'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(settings.value.splitAccountIds, {social.expenses.single.id: 'B'});
    });

    testWidgets('empieza con la cuenta elegida en la hoja de gasto', (tester) async {
      final social = MemorySocial(friends: [ana]);
      final settings = MemorySettings(const WalletSettings());
      final fromSheet = SplitDraft(
        totalMinor: 10000,
        currency: 'PEN',
        title: 'Cena',
        date: now,
        categoryId: 'food',
        accountId: 'B',
      );
      await pump(tester, social, draft: fromSheet, accounts: [bank, savings], settings: settings);
      await tapKey(tester, 'with-ana');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(settings.value.splitAccountIds, {social.expenses.single.id: 'B'});
    });

    testWidgets('sin elegir nada usa la cuenta por defecto', (tester) async {
      final social = MemorySocial(friends: [ana]);
      final settings = MemorySettings(const WalletSettings());
      await pump(tester, social, draft: draft, accounts: [bank, savings], settings: settings);
      await tapKey(tester, 'with-ana');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(settings.value.splitAccountIds, {social.expenses.single.id: 'A'});
    });

    testWidgets('si paga otra persona no se pregunta ni se guarda cuenta', (tester) async {
      final social = MemorySocial(friends: [ana]);
      final settings = MemorySettings(const WalletSettings());
      await pump(tester, social, draft: draft, accounts: [bank, savings], settings: settings);
      await tapKey(tester, 'paid-ana');
      expect(find.text('¿De qué cuenta salió?'), findsNothing);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(settings.value.splitAccountIds, isEmpty);
    });

    testWidgets('al editar conserva la cuenta y cambiarla mueve el gasto de cuenta', (tester) async {
      final e = SharedExpense(
        id: 'e1',
        createdBy: 'u',
        paidBy: 'u',
        participants: const ['u', 'ana'],
        people: const {'u': me, 'ana': ana},
        title: 'Cena',
        date: DateTime(2026, 10, 19),
        currency: 'PEN',
        totalMinor: 6666,
        categoryId: 'food',
        mode: SplitMode.equal,
        shares: const {'u': 3333, 'ana': 3333},
        updatedAt: DateTime(2026, 10, 19),
      );
      final split = Movement(
        id: 'split:e1',
        kind: MovementKind.expense,
        amount: const Money(3333, 'PEN'),
        categoryId: 'food',
        date: e.date,
        createdAt: now,
        origin: MovementOrigin.split,
        accountId: 'A',
        paidMinor: 6666,
      );
      final social = MemorySocial(friends: [ana], expenses: [e]);
      final settings = MemorySettings(const WalletSettings(splitAccountIds: {'e1': 'A'}));
      final movements = await pump(tester, social,
          editing: e, existing: [split], accounts: [bank, savings], settings: settings);
      await tester.tap(find.text('Ahorros'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(settings.value.splitAccountIds, {'e1': 'B'});
      expect(movements.saved.single.accountId, 'B');
    });
  });

  group('edición', () {
    SharedExpense dinner() => SharedExpense(
          id: 'e1',
          createdBy: 'u',
          paidBy: 'u',
          participants: const ['u', 'ana'],
          people: const {'u': me, 'ana': ana},
          title: 'Cena',
          date: DateTime(2026, 10, 19),
          currency: 'PEN',
          totalMinor: 6666,
          categoryId: 'food',
          mode: SplitMode.equal,
          shares: const {'u': 3333, 'ana': 3333},
          updatedAt: DateTime(2026, 10, 19),
        );

    testWidgets('conserva el id y no busca pagos parecidos', (tester) async {
      final social = MemorySocial(friends: [ana], expenses: [dinner()]);
      final movements = await pump(tester, social, editing: dinner(), existing: [googlePay()]);
      expect(find.text('Borrar gasto compartido'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Cena'), 'Cena en Barranco');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('¿Es este pago?'), findsNothing);
      expect(social.expenses.single.id, 'e1');
      expect(social.expenses.single.title, 'Cena en Barranco');
      expect(movements.saved, hasLength(1));
    });

    SharedExpense settledLunch() => dinner().copyWith(
          totalMinor: 5000,
          shares: const {'u': 2500, 'ana': 2500},
          settled: {'ana': Settlement(by: 'ana', at: DateTime(2026, 10, 19, 12))},
        );

    testWidgets('si la parte de un deudor que ya pagó crece, su pago deja de contar', (tester) async {
      final social = MemorySocial(friends: [ana], expenses: [settledLunch()]);
      await pump(tester, social, editing: settledLunch());
      await tester.tap(find.text('S/ 50'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0')); // S/ 50 → S/ 500
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      final e = social.expenses.single;
      expect(e.shareOf('ana'), 25000);
      expect(e.isSettled('ana'), isFalse);
    });

    testWidgets('un pago marcado mientras el editor estaba abierto no se pierde', (tester) async {
      final social = MemorySocial(friends: [ana], expenses: [dinner()]);
      await pump(tester, social, editing: dinner());
      await social.settle('e1', 'ana'); // Ana marca su parte desde su móvil
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Cena'), 'Cena en Barranco');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      final e = social.expenses.single;
      expect(e.title, 'Cena en Barranco');
      expect(e.isSettled('ana'), isTrue);
    });

    testWidgets('si la parte no cambia, el pago se conserva', (tester) async {
      final social = MemorySocial(friends: [ana], expenses: [settledLunch()]);
      await pump(tester, social, editing: settledLunch());
      await tester.enterText(find.widgetWithText(TextField, 'Cena'), 'Almuerzo');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      final e = social.expenses.single;
      expect(e.title, 'Almuerzo');
      expect(e.isSettled('ana'), isTrue);
    });

    testWidgets('Borrar gasto compartido pide confirmación y lo borra', (tester) async {
      final social = MemorySocial(friends: [ana], expenses: [dinner()]);
      await pump(tester, social, editing: dinner());
      await tester.ensureVisible(find.text('Borrar gasto compartido'));
      await tester.tap(find.text('Borrar gasto compartido'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Borrar'));
      await tester.pumpAndSettle();
      expect(social.expenses, isEmpty);
      expect(find.byType(SplitEditorScreen), findsNothing);
    });
  });

  group('hoja de gasto', () {
    Future<MemoryMovements> pumpSheet(WidgetTester tester, MemorySocial social, {Movement? editing}) => pump(
          tester,
          social,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMovementSheet(context, editing: editing),
              child: const Text('hoja'),
            ),
          ),
        );

    testWidgets('el interruptor abre el editor con el importe y no guarda un gasto manual', (tester) async {
      final social = MemorySocial(friends: [ana]);
      final movements = await pumpSheet(tester, social);
      await tester.tap(find.text('hoja'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.byType(SplitEditorScreen), findsOneWidget);
      expect(find.text('S/ 5'), findsOneWidget);
      expect(movements.saved, isEmpty);
    });

    Future<MemoryMovements> pumpGooglePay(WidgetTester tester, MemorySocial social) => pump(
          tester,
          social,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showMovementSheet(
                context,
                draft: MovementDraft(
                  amountMinor: 4250,
                  currency: 'PEN',
                  title: 'Tambo',
                  date: now,
                  origin: MovementOrigin.googlePay,
                ),
              ),
              child: const Text('hoja'),
            ),
          ),
        );

    Future<void> splitFromSheet(WidgetTester tester) async {
      await tester.tap(find.text('hoja'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.byType(SplitEditorScreen), findsOneWidget);
    }

    testWidgets('cerrar el editor vuelve a la hoja con el pago intacto y sin guardar nada', (tester) async {
      final social = MemorySocial(friends: [ana]);
      final movements = await pumpGooglePay(tester, social);
      await splitFromSheet(tester);
      await tester.tap(find.descendant(of: find.byType(SplitEditorScreen), matching: find.byIcon(LucideIcons.x)));
      await tester.pumpAndSettle();
      expect(find.byType(SplitEditorScreen), findsNothing);
      expect(find.byType(MovementSheet), findsOneWidget);
      expect(find.text('S/ 42.50'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Tambo'), findsOneWidget);
      expect(movements.saved, isEmpty);
      expect(social.expenses, isEmpty);
    });

    testWidgets('guardar el reparto cierra el editor y la hoja', (tester) async {
      final social = MemorySocial(friends: [ana]);
      final movements = await pumpGooglePay(tester, social);
      await splitFromSheet(tester);
      await tapKey(tester, 'with-ana');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.byType(SplitEditorScreen), findsNothing);
      expect(find.byType(MovementSheet), findsNothing);
      expect(social.expenses.single.totalMinor, 4250);
      expect(movements.saved, isEmpty);
    });

    testWidgets('sin Amigos disponible no hay interruptor', (tester) async {
      await pumpSheet(tester, MemorySocial(available: false));
      await tester.tap(find.text('hoja'));
      await tester.pumpAndSettle();
      expect(find.text('Dividir con amigos'), findsNothing);
    });

    testWidgets('con un ingreso no hay interruptor', (tester) async {
      final social = MemorySocial(friends: [ana]);
      await pumpSheet(tester, social);
      await tester.tap(find.text('hoja'));
      await tester.pumpAndSettle();
      expect(find.text('Dividir con amigos'), findsOneWidget);
      await tester.tap(find.text('Ingreso'));
      await tester.pumpAndSettle();
      expect(find.text('Dividir con amigos'), findsNothing);
    });

    testWidgets('editando un gasto no hay interruptor', (tester) async {
      final social = MemorySocial(friends: [ana]);
      await pumpSheet(tester, social, editing: googlePay());
      await tester.tap(find.text('hoja'));
      await tester.pumpAndSettle();
      expect(find.text('Dividir con amigos'), findsNothing);
    });
  });
}
