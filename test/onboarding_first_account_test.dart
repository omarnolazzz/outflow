import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/onboarding/presentation/onboarding_controller.dart';
import 'package:outflow/features/onboarding/presentation/onboarding_steps.dart';

import 'support/fakes.dart';

void main() {
  Future<OnboardingController> pump(WidgetTester tester, {Size size = const Size(360, 640)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = OnboardingController(
      short: false,
      settings: MemorySettings(),
      movements: MemoryMovements(),
      accounts: MemoryAccounts(),
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: Scaffold(body: buildStep(OnboardingStep.firstAccount, c))),
    ));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('"Tu primera cuenta" pide nombre y saldo, y cabe a 360 x 640', (tester) async {
    final c = await pump(tester);
    expect(find.text('Tu primera cuenta'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('Yape'), 100, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)));
    await tester.pump();
    await tester.tap(find.text('Yape'));
    await tester.pump();
    expect(c.accountName, 'Yape');

    await tester.enterText(find.byType(TextField), 'Sueldo');
    await tester.pump();
    expect(c.accountName, 'Sueldo');

    await tester.tap(find.text('2'));
    await tester.tap(find.text('5'));
    await tester.tap(find.text('0'));
    await tester.pump();
    expect(c.startingBalanceMinor, 25000);
  });

  testWidgets('con el teclado del sistema abierto se oculta el numérico y no desborda', (tester) async {
    await pump(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(find.text('7'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
