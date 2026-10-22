import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/features/settings/presentation/apple_pay_guide_screen.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nowProvider.overrideWithValue(DateTime(2026, 10, 22, 13)),
        movementRepositoryProvider.overrideWithValue(MemoryMovements()),
        walletSettingsRepositoryProvider.overrideWithValue(MemorySettings()),
        categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
      ],
      child: const MaterialApp(home: ApplePayGuideScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Copiar pone la URL del atajo en el portapapeles', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await pump(tester);
    await tester.scrollUntilVisible(find.text('Copiar'), 200, scrollable: _list);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copiar'));
    await tester.pump();
    expect(copied, kApplePayShortcutUrl);
    expect(kApplePayShortcutUrl, startsWith('outflow://gasto?importe='));
  });

  testWidgets('explica cómo codificar el comercio para nombres con espacios o &', (tester) async {
    await pump(tester);
    expect(find.textContaining('Codificar URL'), findsWidgets);
  });

  testWidgets('Probar abre la hoja de gasto con un pago de ejemplo', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('Probar'), 200, scrollable: _list);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Probar'));
    await tester.pumpAndSettle();
    expect(find.text('Prueba Apple Pay'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
  });
}

/// La lista de la guía (no el desplazable interno del texto de la URL).
final _list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
