import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/friends/data/social_repository.dart';
import 'package:outflow/features/friends/domain/shared_expense.dart';
import 'package:outflow/features/friends/presentation/friends_providers.dart';
import 'package:outflow/features/friends/presentation/friends_screen.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';

const me = Person(uid: 'u', name: 'Gabriel Nolazco', email: 'g@example.com');
const ana = Person(uid: 'ana', name: 'Ana Pérez', email: 'ana@x.com');

SharedExpense dinner({String createdBy = 'u', String paidBy = 'u', bool settled = false}) => SharedExpense(
      id: 'e1',
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

  Future<void> pump(WidgetTester tester, SocialRepository social) async {
    movements = MemoryMovements();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        socialRepositoryProvider.overrideWithValue(social),
        movementRepositoryProvider.overrideWithValue(movements),
        currentAccountProvider.overrideWithValue(
          const Account(uid: 'u', email: 'g@example.com', displayName: 'Gabriel Nolazco'),
        ),
      ],
      child: const MaterialApp(home: FriendsScreen()),
    ));
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
    expect(find.text('Dividir un gasto'), findsNothing);
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

  testWidgets('en un gasto propio hay Borrar y marcar como pagado funciona', (tester) async {
    final social = MemorySocial(friends: [ana], expenses: [dinner()]);
    await pump(tester, social);
    await tester.tap(find.text('Ana Pérez').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cena'));
    await tester.pumpAndSettle();
    expect(find.text('Borrar'), findsOneWidget);
    expect(find.text('Editar'), findsNothing);
    await tester.tap(find.text('Marcar como pagado'));
    await tester.pumpAndSettle();
    expect(social.expenses.single.isSettled('ana'), isTrue);
    expect(find.text('Pagado'), findsWidgets);
  });
}
