import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/cloud/presentation/cloud_sync.dart';
import 'package:outflow/features/friends/domain/shared_expense.dart';
import 'package:outflow/features/friends/domain/split_movements.dart';
import 'package:outflow/features/friends/presentation/friends_providers.dart';
import 'package:outflow/features/home/presentation/home_screen.dart';
import 'package:outflow/features/merchants/domain/entities/merchant.dart';
import 'package:outflow/features/merchants/presentation/merchant_providers.dart';
import 'package:outflow/features/subscriptions/domain/entities/subscription.dart';
import 'package:outflow/features/subscriptions/presentation/subscription_providers.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';

const me = Person(uid: 'u', name: 'Gabriel Nolazco', email: 'g@example.com');
const ana = Person(uid: 'ana', name: 'Ana Pérez', email: 'ana@x.com');

void main() {
  final now = DateTime(2026, 10, 20, 19);

  // Pagaste tú en Tambo con Google Pay y Ana lo repartió con "Pagó: tú".
  SharedExpense tambo({String createdBy = 'ana'}) => SharedExpense(
        id: 'e1',
        createdBy: createdBy,
        paidBy: 'u',
        participants: const ['u', 'ana'],
        people: const {'u': me, 'ana': ana},
        title: 'Tambo',
        date: now.subtract(const Duration(hours: 1)),
        currency: 'PEN',
        totalMinor: 10000,
        categoryId: 'food',
        mode: SplitMode.equal,
        shares: const {'u': 5000, 'ana': 5000},
        updatedAt: now,
      );

  Movement googlePay() => Movement(
        id: 'gp',
        kind: MovementKind.expense,
        amount: const Money(10000, 'PEN'),
        categoryId: 'food',
        date: now.subtract(const Duration(hours: 2)),
        createdAt: now.subtract(const Duration(hours: 2)),
        title: 'Tambo',
        origin: MovementOrigin.googlePay,
      );

  Movement myShare() => Movement(
        id: splitMovementId('e1'),
        kind: MovementKind.expense,
        amount: const Money(5000, 'PEN'),
        categoryId: 'food',
        date: now.subtract(const Duration(hours: 1)),
        createdAt: now.subtract(const Duration(hours: 1)),
        title: 'Tambo',
        origin: MovementOrigin.split,
      );

  Future<void> pump(
    WidgetTester tester, {
    required MemoryMovements movements,
    required MemorySettings settings,
    required MemorySocial social,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        nowProvider.overrideWithValue(now),
        cloudSyncStateProvider.overrideWithValue(CloudSyncState.idle),
        socialRepositoryProvider.overrideWithValue(social),
        movementRepositoryProvider.overrideWithValue(movements),
        walletSettingsRepositoryProvider.overrideWithValue(settings),
        subscriptionsProvider.overrideWith((ref) => Stream.value(const <Subscription>[])),
        categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
        merchantsProvider.overrideWith((ref) => Stream.value(const <Merchant>[])),
        currentAccountProvider.overrideWithValue(
          const Account(uid: 'u', email: 'g@example.com', displayName: 'Gabriel Nolazco'),
        ),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();
  }

  group('dominio', () {
    test('propone el pago que coincide si pagaste tú y lo creó otro', () {
      final r = findSplitPaymentMatches(
        expenses: [tambo()],
        movements: [googlePay(), myShare()],
        myUid: 'u',
        dismissed: const {},
      );
      expect(r.single.expense.id, 'e1');
      expect(r.single.candidates.map((m) => m.id), ['gp']);
    });

    test('nada si lo creaste tú, si ya respondiste o si aún no está tu parte', () {
      List<Object> run(SharedExpense e, {Set<String> dismissed = const {}, bool share = true}) =>
          findSplitPaymentMatches(
            expenses: [e],
            movements: [googlePay(), if (share) myShare()],
            myUid: 'u',
            dismissed: dismissed,
          );
      expect(run(tambo(createdBy: 'u')), isEmpty);
      expect(run(tambo(), dismissed: {'e1'}), isEmpty);
      expect(run(tambo(), share: false), isEmpty);
    });
  });

  testWidgets('Inicio pregunta "¿Es este pago?" y Sí borra el pago de Google Pay', (tester) async {
    final movements = MemoryMovements([googlePay(), myShare()]);
    final settings = MemorySettings(WalletSettings(walletStartedAt: DateTime(2026, 10, 1)));
    await pump(tester, movements: movements, settings: settings, social: MemorySocial(friends: [ana], expenses: [tambo()]));
    expect(find.text('¿Es este pago?'), findsOneWidget);
    await tester.ensureVisible(find.text('Sí'));
    await tester.tap(find.text('Sí'));
    await tester.pumpAndSettle();
    expect(movements.saved.map((m) => m.id), [splitMovementId('e1')]);
    expect(find.text('¿Es este pago?'), findsNothing);
  });

  testWidgets('No oculta la tarjeta para siempre y no borra nada', (tester) async {
    final movements = MemoryMovements([googlePay(), myShare()]);
    final settings = MemorySettings(WalletSettings(walletStartedAt: DateTime(2026, 10, 1)));
    final social = MemorySocial(friends: [ana], expenses: [tambo()]);
    await pump(tester, movements: movements, settings: settings, social: social);
    await tester.ensureVisible(find.text('No, es otro'));
    await tester.tap(find.text('No, es otro'));
    await tester.pumpAndSettle();
    expect(find.text('¿Es este pago?'), findsNothing);
    expect(movements.saved, hasLength(2));
    expect(settings.read().dismissedSplitMatchIds, {'e1'});

    // Al volver a abrir la app sigue oculta.
    await pump(tester, movements: movements, settings: settings, social: social);
    expect(find.text('¿Es este pago?'), findsNothing);
  });
}
