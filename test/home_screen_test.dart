import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/billing_cycle.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/home/presentation/home_screen.dart';
import 'package:outflow/features/merchants/domain/entities/merchant.dart';
import 'package:outflow/features/merchants/presentation/merchant_providers.dart';
import 'package:outflow/features/subscriptions/domain/entities/subscription.dart';
import 'package:outflow/features/subscriptions/domain/subscription_repository.dart';
import 'package:outflow/features/subscriptions/presentation/subscription_providers.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

Movement mv(String id, MovementKind kind, int major, DateTime date, {String title = '', String cat = 'food'}) =>
    Movement(id: id, kind: kind, amount: Money(major * 100, 'PEN'), categoryId: cat, date: date, createdAt: date, title: title);

Subscription netflix({DateTime? cancelQuestion, SubscriptionStatus status = SubscriptionStatus.active}) => Subscription(
      id: 'nf',
      merchantId: 'cat.netflix',
      name: 'Netflix',
      price: const Money(2990, 'PEN'),
      cycle: const BillingCycle.monthly(),
      firstChargeDate: DateTime(2026, 10, 25),
      category: SpendCategory.streaming,
      paymentMethod: const PaymentMethod(kind: PaymentKind.card),
      createdAt: DateTime(2026, 1, 1),
      status: status,
      cancelQuestionCharge: cancelQuestion,
    );

class _NoRepo implements SubscriptionRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class RecordingActions extends SubscriptionActions {
  RecordingActions(super.repo);
  final calls = <String>[];
  @override
  Future<Subscription> resolveCancelQuestion(Subscription s, {required bool wasCharged}) async {
    calls.add('resolve:$wasCharged');
    return s;
  }
}

void main() {
  final now = DateTime(2026, 10, 20, 10);

  Future<RecordingActions> pump(
    WidgetTester tester, {
    List<Movement> movements = const [],
    List<Subscription> subs = const [],
  }) async {
    final actions = RecordingActions(_NoRepo());
    final container = ProviderContainer(overrides: [
      subscriptionActionsProvider.overrideWithValue(actions),
      nowProvider.overrideWithValue(now),
      movementsProvider.overrideWith((ref) => Stream.value(movements)),
      subscriptionsProvider.overrideWith((ref) => Stream.value(subs)),
      walletSettingsProvider.overrideWith((ref) => Stream.value(WalletSettings(walletStartedAt: DateTime(2026, 10, 1)))),
      categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
      merchantsProvider.overrideWith((ref) => Stream.value(const <Merchant>[])),
      currentAccountProvider.overrideWithValue(
        const Account(uid: 'u', email: 'g@example.com', displayName: 'Gabriel Nolazco'),
      ),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();
    return actions;
  }

  testWidgets('muestra "Te queda este mes" con el importe', (tester) async {
    await pump(tester, movements: [
      mv('a', MovementKind.income, 2000, DateTime(2026, 10, 2), title: 'Sueldo', cat: 'salary'),
      mv('b', MovementKind.expense, 350, DateTime(2026, 10, 5), title: 'Almuerzo'),
    ]);
    expect(find.text('Te queda este mes'), findsOneWidget);
    expect(find.textContaining('1,650'), findsWidgets);
    expect(find.text('Almuerzo'), findsOneWidget);
  });

  testWidgets('sin ingresos muestra "Gastado este mes" y el atajo para registrar uno', (tester) async {
    await pump(tester, movements: [mv('b', MovementKind.expense, 120, DateTime(2026, 10, 5))]);
    expect(find.text('Gastado este mes'), findsOneWidget);
    expect(find.text('Registrar ingreso'), findsOneWidget);
  });

  testWidgets('la pregunta de cancelación llama a resolveCancelQuestion(false)', (tester) async {
    final actions = await pump(tester, subs: [
      netflix(cancelQuestion: DateTime(2026, 10, 18), status: SubscriptionStatus.cancelled),
    ]);
    expect(find.text('¿Te llegaron a cobrar este mes?'), findsOneWidget);
    await tester.ensureVisible(find.text('No, la cancelé a tiempo'));
    await tester.tap(find.text('No, la cancelé a tiempo'));
    await tester.pumpAndSettle();
    expect(actions.calls, ['resolve:false']);
  });

  testWidgets('el próximo cobro aparece debajo de la wallet', (tester) async {
    await pump(tester, subs: [netflix()]);
    expect(find.text('Próximo cobro'), findsOneWidget);
    expect(find.text('Netflix'), findsWidgets);
  });
}
