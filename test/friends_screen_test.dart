import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/friends/data/social_repository.dart';
import 'package:outflow/features/friends/domain/shared_expense.dart';
import 'package:outflow/features/friends/presentation/friends_providers.dart';
import 'package:outflow/features/friends/presentation/friends_screen.dart';
import 'package:outflow/features/friends/presentation/split_editor_screen.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';

const me = Person(uid: 'u', name: 'Gabriel Nolazco', email: 'g@example.com');
const ana = Person(uid: 'ana', name: 'Ana Pérez', email: 'ana@x.com');

SharedExpense dinner({String id = 'e1', String createdBy = 'u', String paidBy = 'u', bool settled = false}) => SharedExpense(
      id: id,
      createdBy: createdBy,
      paidBy: paidBy,
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
      settled: settled ? {'ana': Settlement(by: 'u', at: DateTime(2026, 10, 20))} : const {},
    );

void main() {
  late MemoryMovements movements;

  Future<void> pump(WidgetTester tester, SocialRepository social, {List<WalletAccount> accounts = const []}) async {
    movements = MemoryMovements();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        socialRepositoryProvider.overrideWithValue(social),
        movementRepositoryProvider.overrideWithValue(movements),
        if (accounts.isNotEmpty) ...[
          accountRepositoryProvider.overrideWithValue(MemoryAccounts(accounts, movements)),
          walletSettingsRepositoryProvider.overrideWithValue(MemorySettings()),
        ],
        currentAccountProvider.overrideWithValue(
          const Account(uid: 'u', email: 'g@example.com', displayName: 'Gabriel Nolazco'),
        ),
      ],
      child: const MaterialApp(home: FriendsScreen()),
    ));
    // La app ya escucha las cuentas desde Inicio; aquí hay que hacerlo a mano.
    if (accounts.isNotEmpty) {
      ProviderScope.containerOf(tester.element(find.byType(FriendsScreen))).listen(accountsProvider, (_, _) {});
    }
    await tester.pumpAndSettle();
  }

  testWidgets('sin repositorio disponible explica que hay que entrar con Google', (tester) async {
    await pump(tester, MemorySocial(available: false));
    expect(find.textContaining('Entra con tu cuenta de Google'), findsOneWidget);
  });

  testWidgets('vacío invita a añadir amigos', (tester) async {
    await pump(tester, MemorySocial());
    expect(find.text('Añade a tus amigos por su correo de Google.'), findsOneWidget);
  });

  testWidgets('Aceptar una solicitud entrante la convierte en amigo', (tester) async {
    await pump(tester, MemorySocial(incoming: [const FriendRequest(id: 'ana_u', from: ana, to: me)]));
    expect(find.text('Solicitudes'), findsOneWidget);
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();
    expect(find.text('Aceptar'), findsNothing);
    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('Al día'), findsOneWidget);
  });

  testWidgets('las solicitudes enviadas aparecen como Pendiente', (tester) async {
    await pump(tester, MemorySocial(outgoing: [const FriendRequest(id: 'u_ana', from: me, to: ana)]));
    expect(find.text('Pendiente'), findsOneWidget);
  });

  testWidgets('añadir un correo desconocido explica que no usa Outflow', (tester) async {
    final social = MemorySocial();
    await pump(tester, social);
    await tester.tap(find.byTooltip('Opciones'));
    await tester.pumpAndSettle();
    expect(find.text('Dividir un gasto'), findsOneWidget);
    await tester.tap(find.text('Añadir amigo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nadie@x.com');
    await tester.tap(find.text('Enviar solicitud'));
    await tester.pumpAndSettle();
    expect(social.added, ['nadie@x.com']);
    expect(find.text('Esa persona aún no usa Outflow. Pídele que la instale y entre con Google.'), findsOneWidget);
  });

  testWidgets('un amigo con gasto pendiente muestra cuánto te debe', (tester) async {
    await pump(tester, MemorySocial(friends: [ana], expenses: [dinner()]));
    expect(find.textContaining('Te debe'), findsWidgets);
    expect(find.textContaining('33.33'), findsWidgets);
    expect(find.text('Gastos compartidos'), findsOneWidget);
  });

  testWidgets('"Saldar todo" deja al día sin tocar la wallet', (tester) async {
    await pump(tester, MemorySocial(friends: [ana], expenses: [dinner()]));
    await tester.tap(find.text('Ana Pérez').first);
    await tester.pumpAndSettle();
    expect(find.text('Saldar todo'), findsOneWidget);
    await tester.tap(find.text('Saldar todo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saldar')); // confirmación
    await tester.pumpAndSettle();
    expect(find.text('Al día'), findsWidgets);
    expect(find.text('Saldar todo'), findsNothing);
    expect(movements.saved, isEmpty);
  });

  testWidgets('en un gasto creado por otro no hay Editar ni Borrar', (tester) async {
    await pump(tester, MemorySocial(friends: [ana], expenses: [dinner(createdBy: 'ana', paidBy: 'ana')]));
    expect(find.textContaining('Le debes'), findsWidgets);
    await tester.tap(find.text('Ana Pérez').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cena'));
    await tester.pumpAndSettle();
    expect(find.text('Marcar como pagado'), findsOneWidget);
    expect(find.text('Editar'), findsNothing);
    expect(find.text('Borrar'), findsNothing);
  });

  testWidgets('un gasto ya pagado de otro no abre una hoja vacía', (tester) async {
    final paid = dinner(createdBy: 'ana', paidBy: 'ana').copyWith(
      settled: {'u': Settlement(by: 'u', at: DateTime(2026, 10, 20))},
    );
    await pump(tester, MemorySocial(friends: [ana], expenses: [paid]));
    await tester.tap(find.text('Ana Pérez').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cena'));
    await tester.pumpAndSettle();
    expect(find.text('Marcar como pagado'), findsNothing);
    expect(find.text('Editar'), findsNothing);
    expect(find.text('Borrar'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('"Dividir un gasto" del menú + abre el editor', (tester) async {
    await pump(tester, MemorySocial(friends: [ana]));
    await tester.tap(find.byTooltip('Opciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dividir un gasto'));
    await tester.pumpAndSettle();
    expect(find.byType(SplitEditorScreen), findsOneWidget);
  });

  testWidgets('el creador ve Editar y abre el editor con el gasto', (tester) async {
    await pump(tester, MemorySocial(friends: [ana], expenses: [dinner()]));
    await tester.tap(find.text('Ana Pérez').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cena'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(find.byType(SplitEditorScreen), findsOneWidget);
    expect(find.text('Borrar gasto compartido'), findsOneWidget);
  });

  group('personas que no son tus amigos', () {
    const carl = Person(uid: 'carl', name: 'Carlos Díaz', email: 'carl@x.com');

    // Ana (amiga) reparte una cena que pagó Carlos (no es tu amigo).
    SharedExpense carlPaid() => dinner(createdBy: 'ana', paidBy: 'carl').copyWith(
          participants: const ['u', 'ana', 'carl'],
          people: const {'u': me, 'ana': ana, 'carl': carl},
          totalMinor: 9000,
          shares: const {'u': 3000, 'ana': 3000, 'carl': 3000},
        );

    testWidgets('ves lo que le debes, abres su detalle y saldas', (tester) async {
      final social = MemorySocial(friends: [ana], expenses: [carlPaid()]);
      await pump(tester, social);
      expect(find.text('Carlos Díaz'), findsOneWidget);
      expect(find.text('Le debes S/30.00'), findsWidgets);
      await tester.tap(find.text('Carlos Díaz'));
      await tester.pumpAndSettle();
      expect(find.text('Saldar todo'), findsOneWidget);
      await tester.tap(find.text('Cena'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar como pagado'));
      await tester.pumpAndSettle();
      expect(social.expenses.single.isSettled('u'), isTrue);
      expect(find.text('Al día'), findsWidgets);
    });

    testWidgets('el historial abre la hoja del gasto: le pagas a quien no es tu amigo', (tester) async {
      final social = MemorySocial(friends: [ana], expenses: [carlPaid()]);
      await pump(tester, social);
      await tester.tap(find.text('Cena'));
      await tester.pumpAndSettle();
      expect(find.text('Editar'), findsNothing);
      await tester.tap(find.text('Marcar como pagado'));
      await tester.pumpAndSettle();
      expect(social.expenses.single.isSettled('u'), isTrue);
    });

    testWidgets('si pagaste tú, el historial deja marcar el pago de cada deudor', (tester) async {
      final mine = dinner().copyWith(
        participants: const ['u', 'ana', 'carl'],
        people: const {'u': me, 'ana': ana, 'carl': carl},
        totalMinor: 9000,
        shares: const {'u': 3000, 'ana': 3000, 'carl': 3000},
      );
      final social = MemorySocial(friends: [ana], expenses: [mine]);
      await pump(tester, social);
      await tester.tap(find.text('Cena'));
      await tester.pumpAndSettle();
      expect(find.text('Marcar como pagado · Ana'), findsOneWidget);
      await tester.tap(find.text('Marcar como pagado · Carlos'));
      await tester.pumpAndSettle();
      expect(social.expenses.single.isSettled('carl'), isTrue);
      expect(social.expenses.single.isSettled('ana'), isFalse);
    });

    testWidgets('el creador con parte 0 que no pagó abre Editar desde el historial', (tester) async {
      final organized = dinner(createdBy: 'u', paidBy: 'ana').copyWith(
        participants: const ['u', 'ana', 'carl'],
        people: const {'u': me, 'ana': ana, 'carl': carl},
        mode: SplitMode.amounts,
        totalMinor: 6000,
        shares: const {'u': 0, 'ana': 3000, 'carl': 3000},
      );
      await pump(tester, MemorySocial(friends: [ana], expenses: [organized]));
      await tester.tap(find.text('Cena'));
      await tester.pumpAndSettle();
      expect(find.text('Marcar como pagado'), findsNothing);
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(find.byType(SplitEditorScreen), findsOneWidget);
    });
  });

  testWidgets('en un gasto propio hay Borrar y marcar como pagado funciona', (tester) async {
    final social = MemorySocial(friends: [ana], expenses: [dinner()]);
    await pump(tester, social);
    await tester.tap(find.text('Ana Pérez').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cena'));
    await tester.pumpAndSettle();
    expect(find.text('Borrar'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    await tester.tap(find.text('Marcar como pagado'));
    await tester.pumpAndSettle();
    expect(social.expenses.single.isSettled('ana'), isTrue);
    expect(find.text('Pagado'), findsWidgets);
  });

  group('saldar mueve la cuenta si lo eliges', () {
    final bank = WalletAccount(
      id: 'A',
      name: 'Banco',
      type: AccountType.bank,
      currency: 'PEN',
      initialMinor: 0,
      initialDate: kAccountBeginning,
      isDefault: true,
    );

    Future<void> openDinner(WidgetTester tester) async {
      await tester.tap(find.text('Ana Pérez').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cena'));
      await tester.pumpAndSettle();
    }

    testWidgets('te paga un amigo: entra su parte en la cuenta elegida', (tester) async {
      final social = MemorySocial(friends: [ana], expenses: [dinner()]);
      await pump(tester, social, accounts: [bank]);
      await openDinner(tester);
      await tester.tap(find.text('Marcar como pagado'));
      await tester.pumpAndSettle();
      expect(social.expenses.single.isSettled('ana'), isTrue, reason: 'se salda antes de preguntar la cuenta');
      expect(find.text('¿En qué cuenta?'), findsOneWidget);
      await tester.tap(find.text('Banco'));
      await tester.pumpAndSettle();
      final s = movements.saved.single;
      expect(s.id, 'settle:e1:ana');
      expect(s.origin, MovementOrigin.settlement);
      expect(s.adjustmentMinor, 3333);
      expect(s.accountId, 'A');
    });

    testWidgets('pagas tu deuda: sale de la cuenta elegida', (tester) async {
      final social = MemorySocial(friends: [ana], expenses: [dinner(createdBy: 'ana', paidBy: 'ana')]);
      await pump(tester, social, accounts: [bank]);
      await openDinner(tester);
      await tester.tap(find.text('Marcar como pagado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Banco'));
      await tester.pumpAndSettle();
      expect(movements.saved.single.adjustmentMinor, -3333);
    });

    testWidgets('Ninguna salda sin crear ningún movimiento', (tester) async {
      final social = MemorySocial(friends: [ana], expenses: [dinner()]);
      await pump(tester, social, accounts: [bank]);
      await openDinner(tester);
      await tester.tap(find.text('Marcar como pagado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ninguna'));
      await tester.pumpAndSettle();
      expect(social.expenses.single.isSettled('ana'), isTrue);
      expect(movements.saved, isEmpty);
    });

    testWidgets('cerrar la hoja sin elegir tampoco bloquea el saldado', (tester) async {
      final social = MemorySocial(friends: [ana], expenses: [dinner()]);
      await pump(tester, social, accounts: [bank]);
      await openDinner(tester);
      await tester.tap(find.text('Marcar como pagado'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(social.expenses.single.isSettled('ana'), isTrue);
      expect(movements.saved, isEmpty);
    });

    testWidgets('Saldar todo pregunta la cuenta una sola vez', (tester) async {
      final two = dinner(id: 'e2').copyWith(title: 'Almuerzo');
      final social = MemorySocial(friends: [ana], expenses: [dinner(), two]);
      await pump(tester, social, accounts: [bank]);
      await tester.tap(find.text('Ana Pérez').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saldar todo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saldar'));
      await tester.pumpAndSettle();
      expect(find.text('¿En qué cuenta?'), findsOneWidget);
      await tester.tap(find.text('Banco'));
      await tester.pumpAndSettle();
      expect(movements.saved.map((m) => m.id).toSet(), {'settle:e1:ana', 'settle:e2:ana'});
      expect(find.text('¿En qué cuenta?'), findsNothing);
    });
  });
}
