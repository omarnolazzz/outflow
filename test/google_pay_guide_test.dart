import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/settings/presentation/google_pay_guide_screen.dart';
import 'package:outflow/features/wallet/data/payment_listener.dart';

class _FakeListener implements PaymentListener {
  _FakeListener(this.enabled);
  bool enabled;
  int opened = 0;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> openSettings() async => opened++;
}

void main() {
  Future<void> pump(WidgetTester tester, _FakeListener listener) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [paymentListenerProvider.overrideWithValue(listener)],
      child: const MaterialApp(home: GooglePayGuideScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('sin permiso ofrece activarlo y abre los ajustes del teléfono', (tester) async {
    final listener = _FakeListener(false);
    await pump(tester, listener);
    expect(find.text('Dar permiso'), findsOneWidget);
    await tester.tap(find.text('Dar permiso'));
    await tester.pump();
    expect(listener.opened, 1);
  });

  testWidgets('con permiso muestra que está activo', (tester) async {
    await pump(tester, _FakeListener(true));
    expect(find.text('Activado'), findsOneWidget);
    expect(find.text('Dar permiso'), findsNothing);
  });
}
