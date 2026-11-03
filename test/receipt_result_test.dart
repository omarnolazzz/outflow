import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/friends/data/social_repository.dart';
import 'package:outflow/features/friends/domain/shared_expense.dart';
import 'package:outflow/features/friends/presentation/friends_providers.dart';
import 'package:outflow/features/friends/presentation/split_editor_screen.dart';
import 'package:outflow/features/receipts/data/gemini_receipt_reader.dart';
import 'package:outflow/features/receipts/data/text_recognizer.dart';
import 'package:outflow/features/receipts/domain/receipt.dart';
import 'package:outflow/features/wallet/presentation/widgets/movement_sheet.dart';
import 'package:outflow/features/receipts/presentation/receipt_result_screen.dart';
import 'package:outflow/features/receipts/presentation/scan_receipt_flow.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';

void main() {
  reviewFixes();
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

  Future<MemoryMovements> pump(
    WidgetTester tester, {
    List<Movement> existing = const [],
    Widget? home,
    Future<String?> Function(bool)? picker,
    TextRecognizer? recognizer,
    ReceiptReader? reader,
    SocialRepository? social,
    List<WalletAccount>? accounts,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final movements = MemoryMovements(existing);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nowProvider.overrideWithValue(now),
        movementRepositoryProvider.overrideWithValue(movements),
        walletSettingsRepositoryProvider.overrideWithValue(MemorySettings(const WalletSettings())),
        if (accounts != null) accountRepositoryProvider.overrideWithValue(MemoryAccounts(accounts, movements)),
        categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
        imagePickerProvider.overrideWithValue(picker ?? (_) async => null),
        if (recognizer != null) textRecognizerProvider.overrideWithValue(recognizer),
        if (reader != null) receiptReaderProvider.overrideWithValue(reader),
        socialRepositoryProvider.overrideWithValue(social ?? const UnavailableSocialRepository()),
        currentAccountProvider.overrideWithValue(
          const Account(uid: 'u', email: 'g@example.com', displayName: 'Gabriel Nolazco'),
        ),
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
      amount: const Money(4590, 'USD'),
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
    expect(m.amount.currency, 'USD', reason: 'se completa sin cambiarle la moneda');
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

  testWidgets('con Amigos disponible, Dividir con amigos abre el editor con los productos', (tester) async {
    final movements = await pump(tester, social: MemorySocial());
    expect(find.text('Disponible con Amigos'), findsNothing);
    await tester.tap(find.text('Dividir con amigos'));
    await tester.pumpAndSettle();
    expect(find.byType(SplitEditorScreen), findsOneWidget);
    expect(find.text('Productos'), findsOneWidget);
    expect(find.text('S/ 45.90'), findsOneWidget);
    expect(movements.saved, isEmpty);
  });

  group('Dividir con amigos desde el ticket', () {
    const ana = Person(uid: 'ana', name: 'Ana Pérez', email: 'ana@x.com');

    Future<MemoryMovements> pumpPushed(WidgetTester tester, MemorySocial social) async {
      final movements = await pump(
        tester,
        social: social,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ReceiptResultScreen(receipt: receipt),
            )),
            child: const Text('ticket'),
          ),
        ),
      );
      await tester.tap(find.text('ticket'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dividir con amigos'));
      await tester.pumpAndSettle();
      expect(find.byType(SplitEditorScreen), findsOneWidget);
      return movements;
    }

    testWidgets('cerrar el editor vuelve al ticket intacto', (tester) async {
      final social = MemorySocial(friends: [ana]);
      final movements = await pumpPushed(tester, social);
      await tester.tap(find.descendant(of: find.byType(SplitEditorScreen), matching: find.byIcon(LucideIcons.x)));
      await tester.pumpAndSettle();
      expect(find.byType(SplitEditorScreen), findsNothing);
      expect(find.byType(ReceiptResultScreen), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Bodega San Martín'), findsOneWidget);
      expect(movements.saved, isEmpty);
      expect(social.expenses, isEmpty);
    });

    testWidgets('guardar el reparto cierra el editor y el ticket', (tester) async {
      final social = MemorySocial(friends: [ana]);
      await pumpPushed(tester, social);
      await tester.ensureVisible(find.byKey(const ValueKey('with-ana')));
      await tester.tap(find.byKey(const ValueKey('with-ana')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.byType(SplitEditorScreen), findsNothing);
      expect(find.byType(ReceiptResultScreen), findsNothing);
      expect(social.expenses.single.totalMinor, 4590);
    });
  });

  group('cuenta del ticket', () {
    WalletAccount account(String id, String name, {bool isDefault = false, String currency = 'PEN'}) => WalletAccount(
          id: id,
          name: name,
          type: AccountType.bank,
          currency: currency,
          initialMinor: 20000,
          initialDate: kAccountBeginning,
          isDefault: isDefault,
        );

    testWidgets('con varias cuentas empieza en la por defecto y guarda la elegida', (tester) async {
      final movements = await pump(tester, accounts: [account('default', 'BCP', isDefault: true), account('bbva', 'BBVA')]);
      expect(find.text('Cuenta'), findsOneWidget);
      await tester.ensureVisible(find.text('BBVA'));
      await tester.tap(find.text('BBVA'));
      await tester.pump();
      await tester.tap(find.text('Guardar gasto'));
      await tester.pumpAndSettle();
      expect(movements.saved.single.accountId, 'bbva');
    });

    testWidgets('sin tocar el selector guarda la cuenta por defecto', (tester) async {
      final movements = await pump(tester, accounts: [account('default', 'BCP', isDefault: true), account('bbva', 'BBVA')]);
      await tester.tap(find.text('Guardar gasto'));
      await tester.pumpAndSettle();
      expect(movements.saved.single.accountId, 'default');
    });

    testWidgets('con una sola cuenta no hay selector', (tester) async {
      final movements = await pump(tester, accounts: [account('default', 'BCP', isDefault: true)]);
      expect(find.text('Cuenta'), findsNothing);
      await tester.tap(find.text('Guardar gasto'));
      await tester.pumpAndSettle();
      expect(movements.saved.single.accountId, isNull);
    });

    testWidgets('con la moneda del ticket fijada solo se ofrecen cuentas de esa moneda', (tester) async {
      await pump(tester, accounts: [
        account('default', 'BCP', isDefault: true),
        account('bbva', 'BBVA'),
        account('usd', 'Dólares', currency: 'USD'),
      ]);
      expect(find.text('Dólares'), findsNothing);
      expect(find.text('BBVA'), findsOneWidget);
    });
  });

  testWidgets('sin Amigos, Dividir con amigos sigue desactivado', (tester) async {
    await pump(tester, social: MemorySocial(available: false));
    expect(find.text('Disponible con Amigos'), findsOneWidget);
    await tester.tap(find.text('Dividir con amigos'));
    await tester.pumpAndSettle();
    expect(find.byType(SplitEditorScreen), findsNothing);
  });

  testWidgets('cancelar la cámara vuelve sin error ni pantallas nuevas', (tester) async {
    await pump(
      tester,
      home: Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () => scanReceipt(context, fromCamera: true),
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

class _BlankText implements TextRecognizer {
  @override
  Future<String> recognize(String imagePath) async => '   ';
}

class _CountingReader implements ReceiptReader {
  int calls = 0;
  @override
  Future<ReceiptData> read(String text, {required DateTime now, required String fallbackCurrency}) async {
    calls++;
    return const ReceiptData(merchant: 'Inventado', totalMinor: 999);
  }
}

void reviewFixes() {
  final now = DateTime(2026, 10, 20, 19);

  Future<void> pumpWith(WidgetTester tester, Widget home, List<Override> overrides) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nowProvider.overrideWithValue(now),
        movementRepositoryProvider.overrideWithValue(MemoryMovements()),
        walletSettingsRepositoryProvider.overrideWithValue(MemorySettings(const WalletSettings())),
        categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
        socialRepositoryProvider.overrideWithValue(const UnavailableSocialRepository()),
        ...overrides,
      ],
      child: MaterialApp(home: home),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('el botón de escanear de la hoja de gasto abre la cámara', (tester) async {
    var opened = false;
    await pumpWith(
      tester,
      Builder(builder: (context) => TextButton(onPressed: () => showMovementSheet(context), child: const Text('gasto'))),
      [
        imagePickerProvider.overrideWithValue((fromCamera) async {
          opened = fromCamera;
          return null;
        }),
      ],
    );
    await tester.tap(find.text('gasto'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Escanear ticket'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomar foto'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(opened, isTrue);
  });

  testWidgets('sin texto en la foto no se llama a la IA y se avisa', (tester) async {
    final reader = _CountingReader();
    await pumpWith(
      tester,
      Builder(builder: (context) => TextButton(onPressed: () => scanReceipt(context, fromCamera: false), child: const Text('escanear'))),
      [
        imagePickerProvider.overrideWithValue((_) async => '/no/existe.jpg'),
        textRecognizerProvider.overrideWithValue(_BlankText()),
        receiptReaderProvider.overrideWithValue(reader),
      ],
    );
    await tester.tap(find.text('escanear'));
    await tester.pumpAndSettle();
    expect(reader.calls, 0);
    expect(find.textContaining('No pudimos leer el ticket'), findsOneWidget);
  });
}
