import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/billing_cycle.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/cloud/presentation/cloud_sync.dart';
import 'package:outflow/features/friends/domain/shared_expense.dart';
import 'package:outflow/features/friends/presentation/friends_providers.dart';
import 'package:outflow/features/home/presentation/home_screen.dart';
import 'package:outflow/features/merchants/domain/entities/merchant.dart';
import 'package:outflow/features/merchants/presentation/merchant_providers.dart';
import 'package:outflow/features/subscriptions/domain/entities/subscription.dart';
import 'package:outflow/features/subscriptions/domain/subscription_repository.dart';
import 'package:outflow/features/subscriptions/presentation/subscription_providers.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/screens/accounts_screen.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';

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

class _StateCloud extends CloudSync {
  _StateCloud(this.initial);
  final CloudSyncState initial;
  @override
  CloudSyncState build() => initial;
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
  late MemorySettings walletSettings;

  Future<RecordingActions> pump(
    WidgetTester tester, {
    List<Movement> movements = const [],
    List<Subscription> subs = const [],
    MemorySocial? social,
    List<WalletAccount>? accounts,
    bool phone = false,
    CloudSyncState cloud = CloudSyncState.idle,
  }) async {
    if (phone) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }
    final actions = RecordingActions(_NoRepo());
    walletSettings = MemorySettings(WalletSettings(walletStartedAt: DateTime(2026, 10, 1)));
    final container = ProviderContainer(overrides: [
      cloudSyncProvider.overrideWith(() => _StateCloud(cloud)),
      if (social != null) socialRepositoryProvider.overrideWithValue(social),
      if (accounts != null) ...[
        accountRepositoryProvider.overrideWithValue(MemoryAccounts(accounts)),
        walletSettingsRepositoryProvider.overrideWithValue(MemorySettings()),
      ],
      subscriptionActionsProvider.overrideWithValue(actions),
      walletActionsProvider.overrideWithValue(WalletActions(MemoryMovements(movements), walletSettings)),
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

  testWidgets('en unavailable Inicio muestra el aviso de la nube; en live no', (tester) async {
    await pump(tester, phone: true, cloud: CloudSyncState.unavailable);
    expect(find.text('Tu información aún no se está guardando en la nube'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en live Inicio no muestra el aviso de la nube', (tester) async {
    await pump(tester, phone: true, cloud: CloudSyncState.live);
    expect(find.text('Tu información aún no se está guardando en la nube'), findsNothing);
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
    expect(walletSettings.read().deletedChargeIds, {'sub:nf:2026-10-18'});
  });

  testWidgets('el próximo cobro aparece debajo de la wallet', (tester) async {
    await pump(tester, subs: [netflix()]);
    expect(find.text('Próximo cobro'), findsOneWidget);
    expect(find.text('Netflix'), findsWidgets);
  });

  SharedExpense dinner({bool settled = false}) => SharedExpense(
        id: 'e1',
        createdBy: 'u',
        paidBy: 'u',
        participants: const ['u', 'ana'],
        people: const {
          'u': Person(uid: 'u', name: 'Gabriel Nolazco', email: 'g@example.com'),
          'ana': Person(uid: 'ana', name: 'Ana Pérez', email: 'ana@x.com'),
        },
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

  testWidgets('Inicio muestra "Te deben" cuando hay saldo con amigos', (tester) async {
    await pump(tester, social: MemorySocial(expenses: [dinner()]));
    expect(find.textContaining('Te deben'), findsOneWidget);
    expect(find.textContaining('33.33'), findsWidgets);
  });

  testWidgets('Inicio no muestra la tarjeta de deudas sin saldo', (tester) async {
    await pump(tester, social: MemorySocial(expenses: [dinner(settled: true)]));
    expect(find.textContaining('Te deben'), findsNothing);
    expect(find.textContaining('Debes'), findsNothing);
  });

  WalletAccount account(String id, String name, {int initial = 0, String currency = 'PEN', bool isDefault = false}) =>
      WalletAccount(
        id: id,
        name: name,
        type: AccountType.bank,
        currency: currency,
        initialMinor: initial,
        initialDate: kAccountBeginning,
        isDefault: isDefault,
      );

  testWidgets('Inicio muestra "Saldo en cuentas" con el total en la moneda principal y las otras aparte', (tester) async {
    await pump(tester, accounts: [
      account('default', 'BCP', initial: 15000, isDefault: true),
      account('dale', 'Dale', initial: 2500),
      account('usd', 'Dólares', initial: 12000, currency: 'USD'),
    ]);
    expect(find.text('Saldo en cuentas'), findsOneWidget);
    expect(find.textContaining('175.00'), findsOneWidget, reason: '150 + 25 en soles');
    expect(find.textContaining('120.00'), findsOneWidget);
    expect(find.textContaining('en otras monedas'), findsWidgets);
    expect(find.text('3 cuentas'), findsOneWidget);

    await tester.tap(find.text('Saldo en cuentas'));
    await tester.pumpAndSettle();
    expect(find.text('Cuentas'), findsOneWidget);
    expect(find.byType(AccountsScreen), findsOneWidget);
  });

  testWidgets('Inicio no cuenta las cuentas archivadas en el total', (tester) async {
    await pump(tester, accounts: [
      account('default', 'BCP', initial: 15000, isDefault: true),
      account('old', 'Vieja', initial: 99900).copyWith(archived: true),
    ]);
    expect(find.textContaining('150.00'), findsOneWidget);
    expect(find.text('1 cuenta'), findsOneWidget);
    expect(find.textContaining('1,149'), findsNothing);
  });

  testWidgets('Inicio avisa de lo que está por revisar, y sin nada no ocupa sitio', (tester) async {
    await pump(tester, movements: [mv('b', MovementKind.expense, 12, DateTime(2026, 10, 5))]);
    expect(find.textContaining('por revisar'), findsNothing);

    await pump(tester, movements: [
      mv('a', MovementKind.expense, 12, DateTime(2026, 10, 5)).copyWith(needsReview: true),
      mv('b', MovementKind.expense, 13, DateTime(2026, 10, 6)).copyWith(needsReview: true),
    ]);
    expect(find.text('2 movimientos por revisar'), findsOneWidget);
  });

  testWidgets('sin datos y a 360 px Inicio no desborda', (tester) async {
    await pump(tester, phone: true, accounts: [account('default', 'Mi cuenta', isDefault: true)]);
    expect(find.text('Saldo en cuentas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
