import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/subscriptions/presentation/subscription_providers.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/screens/summary_screen.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

Movement exp(String id, int major, String cat, DateTime d) => Movement(
      id: id,
      kind: MovementKind.expense,
      amount: Money(major * 100, 'PEN'),
      categoryId: cat,
      date: d,
      createdAt: d,
    );

void main() {
  final now = DateTime(2026, 10, 20);

  Future<void> pump(WidgetTester tester, List<Movement> movements) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nowProvider.overrideWithValue(now),
        movementsProvider.overrideWith((ref) => Stream.value(movements)),
        subscriptionsProvider.overrideWith((ref) => Stream.value(const [])),
        walletSettingsProvider.overrideWith((ref) => Stream.value(WalletSettings(walletStartedAt: DateTime(2026, 5, 1)))),
        categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
      ],
      child: const MaterialApp(home: SummaryScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('la leyenda reparte el gasto por categoría en porcentajes', (tester) async {
    await pump(tester, [
      exp('a', 300, 'food', DateTime(2026, 10, 3)),
      exp('b', 100, 'transport', DateTime(2026, 10, 4)),
    ]);
    expect(find.text('Comida'), findsOneWidget);
    expect(find.text('Transporte'), findsOneWidget);
    expect(find.text('75 %'), findsOneWidget);
    expect(find.text('25 %'), findsOneWidget);
  });

  testWidgets('compara con el mes anterior', (tester) async {
    await pump(tester, [
      exp('a', 200, 'food', DateTime(2026, 9, 3)),
      exp('b', 300, 'food', DateTime(2026, 10, 3)),
    ]);
    expect(find.textContaining('50 % más que en septiembre'), findsOneWidget);
  });

  testWidgets('sin movimientos muestra un estado vacío', (tester) async {
    await pump(tester, const []);
    expect(find.text('Aún no hay gastos este mes.'), findsOneWidget);
  });
}
