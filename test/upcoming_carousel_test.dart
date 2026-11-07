import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/billing_cycle.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/merchants/domain/entities/merchant.dart';
import 'package:outflow/features/subscriptions/domain/dashboard_summary.dart';
import 'package:outflow/features/subscriptions/domain/entities/subscription.dart';
import 'package:outflow/features/subscriptions/presentation/widgets/upcoming_carousel.dart';

UpcomingItem item(int i) => UpcomingItem(
      subscription: Subscription(
        id: 's$i',
        merchantId: 'm$i',
        name: 'Servicio $i',
        price: const Money(1990, 'PEN'),
        cycle: const BillingCycle.monthly(),
        firstChargeDate: DateTime(2026, 11, 10 + i),
        category: SpendCategory.streaming,
        paymentMethod: const PaymentMethod(kind: PaymentKind.card),
        createdAt: DateTime(2026, 1, 1),
      ),
      kind: UpcomingKind.charge,
      date: DateTime(2026, 11, 10 + i),
      daysLeft: 3 + i,
      cycleProgress: 0.5,
    );

/// Opacidad de la entrada (la más externa) de la tarjeta con [title].
double entranceOpacity(WidgetTester tester, String title) => tester
    .widgetList<Opacity>(find.ancestor(of: find.text(title), matching: find.byType(Opacity)))
    .last
    .opacity;

void main() {
  testWidgets('al deslizar, cada tarjeta que llega ya está visible (sin entrada retrasada)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpcomingCarousel(items: [for (var i = 0; i < 9; i++) item(i)], merchants: const {}, onOpen: (_) {}),
      ),
    ));
    await tester.pump(const Duration(seconds: 2)); // termina la entrada inicial

    for (var i = 1; i < 9; i++) {
      await tester.drag(find.byType(PageView), const Offset(-320, 0));
      // Solo el tiempo del deslizamiento: lo que llega debe verse ya.
      for (var f = 0; f < 8; f++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      final next = 'Servicio ${(i + 1).clamp(0, 8)}';
      if (find.text(next).evaluate().isNotEmpty) {
        expect(entranceOpacity(tester, next), greaterThan(0.99), reason: next);
      }
    }
  });
}
