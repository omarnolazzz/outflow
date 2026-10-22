import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/wallet/domain/apple_pay_link.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/deep_link_provider.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';
import 'package:outflow/features/wallet/presentation/widgets/movement_sheet.dart';

import 'support/fakes.dart';

void main() {
  final now = DateTime(2026, 10, 22, 13, 0);
  final draft = MovementDraft(
    amountMinor: 1250,
    currency: 'PEN',
    title: 'Starbucks',
    date: now,
    origin: MovementOrigin.applePay,
    note: 'Tarjeta: Visa',
  );

  Future<MemoryMovements> pump(WidgetTester tester, {List<Movement> existing = const []}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final movements = MemoryMovements(existing);
    final container = ProviderContainer(overrides: [
      nowProvider.overrideWithValue(now),
      movementRepositoryProvider.overrideWithValue(movements),
      walletSettingsRepositoryProvider.overrideWithValue(MemorySettings(const WalletSettings())),
      categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMovementSheet(context, draft: draft),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return movements;
  }

  testWidgets('la hoja llega rellenada y Guardar crea el gasto de Apple Pay', (tester) async {
    final movements = await pump(tester);
    expect(find.text('S/ 12.50'), findsOneWidget);
    expect(find.text('Starbucks'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final m = movements.saved.single;
    expect(m.origin, MovementOrigin.applePay);
    expect(m.amount, const Money(1250, 'PEN'));
    expect(m.title, 'Starbucks');
    expect(m.categoryId, 'food', reason: 'sugerida por palabra clave');
    expect(m.note, 'Tarjeta: Visa');
  });

  testWidgets('avisa de un posible duplicado pero deja guardar', (tester) async {
    final previous = Movement(
      id: 'p',
      kind: MovementKind.expense,
      amount: const Money(1250, 'PEN'),
      categoryId: 'food',
      date: now.subtract(const Duration(minutes: 1)),
      createdAt: now.subtract(const Duration(minutes: 1)),
      title: 'Starbucks',
      origin: MovementOrigin.applePay,
    );
    final movements = await pump(tester, existing: [previous]);
    expect(find.textContaining('Posible duplicado'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(movements.saved, hasLength(2));
  });

  test('varios pagos con la app bloqueada no se pierden', () {
    final pending = PendingLink();
    final second = MovementDraft(amountMinor: 900, title: 'Tambo', origin: MovementOrigin.applePay, date: now);
    pending.offer(draft, ready: false);
    pending.offer(second, ready: false);
    expect(pending.takeAll(), [draft, second]);
    expect(pending.takeAll(), isEmpty);
  });

  test('un enlace recibido con la app bloqueada se entrega una sola vez al desbloquear', () {
    final pending = PendingLink();
    expect(pending.offer(draft, ready: false), isNull);
    expect(pending.takeAll(), [draft]);
    expect(pending.takeAll(), isEmpty);
    expect(pending.offer(draft, ready: true), draft);
    expect(pending.takeAll(), isEmpty);
  });
}
