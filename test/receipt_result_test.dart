import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/receipts/domain/receipt.dart';
import 'package:outflow/features/receipts/presentation/receipt_result_screen.dart';
import 'package:outflow/features/receipts/presentation/scan_receipt_flow.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';

void main() {
  final now = DateTime(2026, 10, 20, 19);
  final receipt = ReceiptData(
    merchant: 'Bodega San Martín',
    date: DateTime(2026, 10, 20),
    totalMinor: 4590,
    currency: 'PEN',
    items: const [
      ReceiptItem(name: 'Gaseosa 500ml', quantity: 2, amountMinor: 700),
      ReceiptItem(name: 'Pan de molde', amountMinor: 850),
    ],
    fromAi: true,
  );

  Future<MemoryMovements> pump(WidgetTester tester, {List<Movement> existing = const [], Widget? home}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final movements = MemoryMovements(existing);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nowProvider.overrideWithValue(now),
        movementRepositoryProvider.overrideWithValue(movements),
        walletSettingsRepositoryProvider.overrideWithValue(MemorySettings(const WalletSettings())),
        categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
        imagePickerProvider.overrideWithValue((_) async => null),
      ],
      child: MaterialApp(home: home ?? ReceiptResultScreen(receipt: receipt)),
    ));
    await tester.pumpAndSettle();
    return movements;
  }

  testWidgets('muestra lo leído y guarda un gasto de ticket con los productos en la nota', (tester) async {
    final movements = await pump(tester);
    expect(find.text('Leído con IA'), findsOneWidget);
    expect(find.text('Gaseosa 500ml'), findsOneWidget);
    await tester.tap(find.text('Guardar gasto'));
    await tester.pumpAndSettle();
    final m = movements.saved.single;
    expect(m.origin, MovementOrigin.ticket);
    expect(m.amount, const Money(4590, 'PEN'));
    expect(m.title, 'Bodega San Martín');
    expect(m.note, contains('Gaseosa 500ml'));
    expect(m.note, contains('Pan de molde'));
  });

  testWidgets('si el pago ya estaba registrado, lo completa en vez de duplicarlo', (tester) async {
    final applePay = Movement(
      id: 'ap',
      kind: MovementKind.expense,
      amount: const Money(4590, 'PEN'),
      categoryId: 'groceries',
      date: now.subtract(const Duration(hours: 1)),
      createdAt: now.subtract(const Duration(hours: 1)),
      title: 'POS BODEGA',
      origin: MovementOrigin.applePay,
    );
    final movements = await pump(tester, existing: [applePay]);
    await tester.tap(find.text('Guardar gasto'));
    await tester.pumpAndSettle();
    expect(find.text('¿Es este pago?'), findsOneWidget);
    await tester.tap(find.text('POS BODEGA'));
    await tester.pumpAndSettle();
    expect(movements.saved, hasLength(1));
    final m = movements.saved.single;
    expect(m.id, 'ap');
    expect(m.title, 'Bodega San Martín');
    expect(m.note, contains('Gaseosa 500ml'));
    expect(m.origin, MovementOrigin.applePay);
  });

  testWidgets('"No, es otro" crea un gasto nuevo', (tester) async {
    final other = Movement(
      id: 'x',
      kind: MovementKind.expense,
      amount: const Money(4590, 'PEN'),
      categoryId: 'food',
      date: now,
      createdAt: now,
      title: 'Otra cosa',
    );
    final movements = await pump(tester, existing: [other]);
    await tester.tap(find.text('Guardar gasto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, es otro'));
    await tester.pumpAndSettle();
    expect(movements.saved, hasLength(2));
  });

  testWidgets('cancelar la cámara vuelve sin error ni pantallas nuevas', (tester) async {
    await pump(
      tester,
      home: Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () => scanReceipt(context, ref, fromCamera: true),
          child: const Text('escanear'),
        ),
      ),
    );
    await tester.tap(find.text('escanear'));
    await tester.pumpAndSettle();
    expect(find.text('escanear'), findsOneWidget);
    expect(find.textContaining('Leyendo'), findsNothing);
  });
}
