import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/capture/data/capture_inbox.dart';
import 'package:outflow/features/capture/presentation/capture_providers.dart';
import 'package:outflow/features/capture/presentation/review_card.dart';
import 'package:outflow/features/capture/presentation/review_screen.dart';
import 'package:outflow/features/friends/presentation/friends_providers.dart';
import 'package:outflow/features/subscriptions/domain/entities/subscription.dart';
import 'package:outflow/features/subscriptions/presentation/subscription_providers.dart';
import 'package:outflow/features/wallet/domain/account_balances.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/month_summary.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';
import 'package:outflow/features/wallet/presentation/widgets/movement_row.dart';
import 'package:outflow/features/wallet/presentation/widgets/movement_sheet.dart';

import 'support/fakes.dart';

final _now = DateTime(2026, 11, 3, 12);

Movement _captured(
  String id,
  int minor, {
  String title = 'Tambo',
  MovementKind kind = MovementKind.expense,
  String note = '',
  bool needsReview = true,
  String account = 'a',
}) =>
    Movement(
      id: id,
      kind: kind,
      amount: Money(minor, 'PEN'),
      categoryId: kind == MovementKind.expense ? 'food' : kOtherIncomeCategoryId,
      date: _now,
      createdAt: _now,
      title: title,
      note: note,
      origin: MovementOrigin.capture,
      needsReview: needsReview,
      accountId: account,
    );

WalletAccount _acc(String id, String name, {bool isDefault = false, String currency = 'PEN'}) => WalletAccount(
      id: id,
      name: name,
      type: AccountType.bank,
      currency: currency,
      initialMinor: 100000,
      initialDate: kAccountBeginning,
      isDefault: isDefault,
    );

void main() {
  late MemoryMovements repo;

  Future<ProviderContainer> pump(WidgetTester tester, Widget home, List<Movement> movements, {List<WalletAccount>? accounts}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    repo = MemoryMovements(movements);
    final settings = MemorySettings(WalletSettings(walletStartedAt: DateTime(2026, 10, 1)));
    final c = ProviderContainer(overrides: [
      movementRepositoryProvider.overrideWithValue(repo),
      accountRepositoryProvider.overrideWithValue(MemoryAccounts(accounts ?? [_acc('a', 'Principal', isDefault: true), _acc('b', 'Dale')])),
      walletSettingsRepositoryProvider.overrideWithValue(settings),
      nowProvider.overrideWithValue(_now),
      walletSettingsProvider.overrideWith((ref) => settings.watch()),
      categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
      subscriptionsProvider.overrideWith((ref) => Stream.value(const <Subscription>[])),
      socialRepositoryProvider.overrideWithValue(MemorySocial(available: false)),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp(home: home)));
    await tester.pumpAndSettle();
    return c;
  }

  group('MovementRow', () {
    testWidgets('marca lo que está por revisar', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MovementRow(movement: _captured('m', 500), category: null)),
      ));
      expect(find.textContaining('por revisar'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MovementRow(movement: _captured('m', 500, needsReview: false), category: null)),
      ));
      expect(find.textContaining('por revisar'), findsNothing);
    });
  });

  group('ReviewCard', () {
    testWidgets('sin nada por revisar no se muestra', (tester) async {
      await pump(tester, const Scaffold(body: ReviewCard()), [_captured('m', 500, needsReview: false)]);
      expect(find.textContaining('por revisar'), findsNothing);
    });

    testWidgets('singular y plural', (tester) async {
      await pump(tester, const Scaffold(body: ReviewCard()), [_captured('m', 500)]);
      expect(find.text('1 movimiento por revisar'), findsOneWidget);
    });

    testWidgets('N movimientos y al tocar abre la revisión', (tester) async {
      await pump(tester, const Scaffold(body: ReviewCard()), [_captured('m', 500), _captured('n', 600)]);
      expect(find.text('2 movimientos por revisar'), findsOneWidget);
      await tester.tap(find.text('2 movimientos por revisar'));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewScreen), findsOneWidget);
    });
  });

  group('ReviewScreen', () {
    testWidgets('solo lista lo que está por revisar', (tester) async {
      await pump(tester, const ReviewScreen(), [_captured('m', 500), _captured('n', 600, title: 'Otro', needsReview: false)]);
      expect(find.text('Tambo'), findsOneWidget);
      expect(find.text('Otro'), findsNothing);
    });

    testWidgets('confirmar quita la marca y lo deja igual', (tester) async {
      await pump(tester, const ReviewScreen(), [_captured('m', 500)]);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      final m = repo.saved.single;
      expect(m.needsReview, isFalse);
      expect(m.amount.minor, 500);
      expect(m.title, 'Tambo');
      expect(find.text('Tambo'), findsNothing);
      expect(find.textContaining('Nada por revisar'), findsOneWidget);
    });

    testWidgets('confirmar un "¿duplicado?" le quita la nota: ya es un pago real', (tester) async {
      await pump(tester, const ReviewScreen(), [_captured('m', 500, note: '¿duplicado?')]);
      expect(find.textContaining('¿duplicado?'), findsOneWidget);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(repo.saved.single.note, '');
    });

    testWidgets('borrar recalcula el saldo y se puede deshacer', (tester) async {
      final c = await pump(tester, const ReviewScreen(), [_captured('m', 500)]);
      final sub = c.listen(accountBalancesProvider, (_, _) {});
      addTearDown(sub.close);
      await tester.pumpAndSettle();
      expect(c.read(accountBalancesProvider).value!['a'], 99500);

      await tester.tap(find.text('Borrar'));
      await tester.pumpAndSettle();
      expect(repo.saved, isEmpty);
      expect(c.read(accountBalancesProvider).value!['a'], 100000);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(repo.saved.single.needsReview, isTrue);
      expect(c.read(accountBalancesProvider).value!['a'], 99500);
    });

    testWidgets('editar abre la hoja de gasto; guardar corrige y da por revisado', (tester) async {
      await pump(tester, const ReviewScreen(), [_captured('m', 500)]);
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(find.byType(MovementSheet), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(repo.saved.single.needsReview, isFalse);
      expect(repo.saved.single.origin, MovementOrigin.capture);
      expect(repo.saved.single.accountId, 'a');
    });

    testWidgets('desde la hoja se convierte en transferencia', (tester) async {
      final c = await pump(tester, const ReviewScreen(), [_captured('m', 500)]);
      final sub = c.listen(accountBalancesProvider, (_, _) {});
      addTearDown(sub.close);
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Transferencia'));
      await tester.tap(find.text('Transferencia'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text('Dale')));
      await tester.pumpAndSettle();

      final m = repo.saved.single;
      expect(m.id, 'm');
      expect(m.kind, MovementKind.transfer);
      expect(m.accountId, 'a');
      expect(m.toAccountId, 'b');
      expect(m.needsReview, isFalse);
      expect(find.byType(MovementSheet), findsNothing);
      expect(c.read(accountBalancesProvider).value, {'a': 99500, 'b': 100500});
    });

    testWidgets('sin otra cuenta de esa moneda no se ofrece la transferencia', (tester) async {
      await pump(
        tester,
        const ReviewScreen(),
        [_captured('m', 500)],
        accounts: [_acc('a', 'Principal', isDefault: true), _acc('u', 'Dólares', currency: 'USD')],
      );
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(find.text('Transferencia'), findsNothing);
    });

    testWidgets('una transferencia por revisar no se abre en la hoja de gasto', (tester) async {
      await pump(tester, const ReviewScreen(), [
        _captured('t', 500, kind: MovementKind.transfer).copyWith(toAccountId: 'b', categoryId: kNoCategoryId),
      ]);
      expect(find.text('Confirmar'), findsOneWidget);
      expect(find.text('Borrar'), findsOneWidget);
      expect(find.text('Editar'), findsNothing);
    });
  });

  test('un movimiento por revisar cuenta en MonthSummary', () {
    final s = MonthSummary.compute(
      movements: [
        _captured('g', 500),
        _captured('i', 2000, kind: MovementKind.income),
      ],
      subscriptions: const [],
      settings: WalletSettings(walletStartedAt: DateTime(2026, 10, 1)),
      month: DateTime(2026, 11),
      now: _now,
    );
    expect(s.expense.minor, 500);
    expect(s.income.minor, 2000);
  });

  test('un movimiento por revisar cuenta en el saldo', () {
    final a = _acc('a', 'Principal', isDefault: true);
    expect(computeBalances([a], [_captured('g', 500)])['a'], 99500);
  });

  test('reviewMovementsProvider: los más recientes primero', () async {
    final older = Movement(
      id: 'old',
      kind: MovementKind.expense,
      amount: const Money(1, 'PEN'),
      categoryId: 'food',
      date: _now.subtract(const Duration(days: 2)),
      createdAt: _now,
      needsReview: true,
    );
    final c = ProviderContainer(overrides: [
      movementsProvider.overrideWith((ref) => Stream.value([older, _captured('new', 2)])),
    ]);
    addTearDown(c.dispose);
    final sub = c.listen(reviewMovementsProvider, (_, _) {});
    addTearDown(sub.close);
    await pumpEventQueue();
    expect(c.read(reviewMovementsProvider).map((m) => m.id), ['new', 'old']);
  });

  test('borrar toda la información vacía la bandeja', () async {
    final dir = Directory.systemTemp.createTempSync('outflow_inbox_erase');
    addTearDown(() => dir.deleteSync(recursive: true));
    final inbox = CaptureInbox(directory: () async => dir);
    await inbox.add(CaptureEvent(sourceKey: 's', sourceLabel: 's', text: 'Pagaste S/ 5.00', receivedAt: _now));
    await inbox.clear();
    expect(dir.listSync(), isEmpty);
  });
}
