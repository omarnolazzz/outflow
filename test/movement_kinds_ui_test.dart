import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/friends/data/social_repository.dart';
import 'package:outflow/features/friends/presentation/friends_providers.dart';
import 'package:outflow/features/settings/presentation/category_editor_screen.dart';
import 'package:outflow/features/subscriptions/presentation/subscription_providers.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/screens/movements_screen.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';
import 'package:outflow/features/wallet/presentation/widgets/movement_row.dart';
import 'package:outflow/features/wallet/presentation/widgets/movement_sheet.dart';

import 'support/fakes.dart';

final _now = DateTime(2026, 10, 20, 10);

Movement _m(
  String id,
  MovementKind kind,
  int minor, {
  String title = '',
  String categoryId = kNoCategoryId,
  String? account = 'A',
  String? to,
  bool incoming = false,
  int? adjustment,
  MovementOrigin origin = MovementOrigin.manual,
}) =>
    Movement(
      id: id,
      kind: kind,
      amount: Money(minor, 'PEN'),
      categoryId: categoryId,
      date: _now,
      createdAt: _now,
      title: title,
      origin: origin,
      accountId: account,
      toAccountId: to,
      transferIncoming: incoming,
      adjustmentMinor: adjustment,
    );

void main() {
  group('MovementRow', () {
    Future<void> pumpRow(WidgetTester tester, Movement m) => tester.pumpWidget(MaterialApp(
          home: Scaffold(body: MovementRow(movement: m, category: null)),
        ));

    testWidgets('una transferencia se ve con su icono, sus cuentas y sin signo', (tester) async {
      await pumpRow(tester, _m('t', MovementKind.transfer, 4000, title: 'BCP → Dale', to: 'B'));
      expect(tester.takeException(), isNull);
      expect(find.text('BCP → Dale'), findsOneWidget);
      expect(find.text('Transferencia'), findsOneWidget);
      expect(find.byIcon(LucideIcons.arrowLeftRight), findsOneWidget);
      expect(find.textContaining('no descuenta'), findsNothing);
      expect(find.textContaining('+'), findsNothing);
      expect(find.textContaining('−'), findsNothing);
    });

    testWidgets('sin el otro lado lleva el signo de su sentido', (tester) async {
      await pumpRow(tester, _m('t', MovementKind.transfer, 4000, incoming: true));
      expect(find.textContaining('+'), findsOneWidget);
      expect(find.text('Transferencia'), findsOneWidget, reason: 'sin título, se nombra por su tipo');
      await pumpRow(tester, _m('t', MovementKind.transfer, 4000));
      await tester.pump();
      expect(find.textContaining('−'), findsOneWidget);
    });

    testWidgets('un ajuste se ve con su icono y el signo de la diferencia', (tester) async {
      await pumpRow(tester, _m('a', MovementKind.adjustment, 800, adjustment: -800));
      expect(tester.takeException(), isNull);
      expect(find.text('Ajuste de saldo'), findsOneWidget);
      expect(find.byIcon(LucideIcons.scale), findsOneWidget);
      expect(find.textContaining('−'), findsOneWidget);
      expect(find.textContaining('no descuenta'), findsNothing);

      await pumpRow(tester, _m('a', MovementKind.adjustment, 800, adjustment: 800));
      await tester.pump();
      expect(find.textContaining('+'), findsOneWidget);
    });
  });

  group('Movimientos', () {
    Future<void> pump(WidgetTester tester, List<Movement> items) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          nowProvider.overrideWithValue(_now),
          movementRepositoryProvider.overrideWithValue(MemoryMovements(items)),
          subscriptionsProvider.overrideWith((ref) => Stream.value(const [])),
          walletSettingsRepositoryProvider.overrideWithValue(MemorySettings(WalletSettings(walletStartedAt: DateTime(2026, 5, 1)))),
          categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
          socialRepositoryProvider.overrideWithValue(const UnavailableSocialRepository()),
        ],
        child: const MaterialApp(home: MovementsScreen()),
      ));
      await tester.pumpAndSettle();
    }

    final all = [
      _m('g', MovementKind.expense, 1000, title: 'Almuerzo', categoryId: 'food'),
      _m('i', MovementKind.income, 5000, title: 'Pago de octubre', categoryId: 'salary'),
      _m('t', MovementKind.transfer, 4000, title: 'BCP → Dale', to: 'B'),
      _m('a', MovementKind.adjustment, 800, title: 'Ajuste de saldo', adjustment: -800),
    ];

    testWidgets('en Todos se ven; en Gastos e Ingresos no', (tester) async {
      await pump(tester, all);
      expect(find.text('BCP → Dale'), findsOneWidget);
      expect(find.text('Ajuste de saldo'), findsOneWidget);

      await tester.tap(find.text('Ingresos'));
      await tester.pumpAndSettle();
      expect(find.text('Pago de octubre'), findsOneWidget);
      expect(find.text('Almuerzo'), findsNothing);
      expect(find.text('BCP → Dale'), findsNothing);
      expect(find.text('Ajuste de saldo'), findsNothing);

      await tester.tap(find.text('Gastos'));
      await tester.pumpAndSettle();
      expect(find.text('Almuerzo'), findsOneWidget);
      expect(find.text('Pago de octubre'), findsNothing);
      expect(find.text('BCP → Dale'), findsNothing);
      expect(find.text('Ajuste de saldo'), findsNothing);
    });

    testWidgets('el total del día no los cuenta', (tester) async {
      await pump(tester, all);
      // Pago 50.00 − Almuerzo 10.00; sin los 40.00 ni los 8.00.
      final totals = find.textContaining('+').evaluate().map((e) => (e.widget as Text).data).toList();
      expect(totals.any((t) => t!.contains('40.00')), isTrue, reason: 'total del día: $totals');

      await pump(tester, [all[2], all[3]]);
      expect(find.textContaining('+'), findsNothing, reason: 'un día solo con estos no tiene total');
    });

    testWidgets('tocarlos no abre la hoja de gasto', (tester) async {
      await pump(tester, all);
      await tester.tap(find.text('BCP → Dale'));
      await tester.pumpAndSettle();
      expect(find.text('Guardar'), findsNothing);
      await tester.tap(find.text('Ajuste de saldo'));
      await tester.pumpAndSettle();
      expect(find.text('Guardar'), findsNothing);
    });
  });

  testWidgets('la hoja de movimiento solo ofrece Gasto e Ingreso', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nowProvider.overrideWithValue(_now),
        movementRepositoryProvider.overrideWithValue(MemoryMovements()),
        socialRepositoryProvider.overrideWithValue(const UnavailableSocialRepository()),
        walletSettingsRepositoryProvider.overrideWithValue(MemorySettings()),
        categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
      ],
      child: const MaterialApp(home: MovementSheet(kind: MovementKind.expense)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Gasto'), findsOneWidget);
    expect(find.text('Ingreso'), findsOneWidget);
  });

  testWidgets('el editor de categorías solo ofrece Gastos e Ingresos', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories()))],
      child: const MaterialApp(home: CategoryEditorScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Gastos'), findsOneWidget);
    expect(find.text('Ingresos'), findsOneWidget);
  });
}
