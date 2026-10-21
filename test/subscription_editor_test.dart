import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/billing_cycle.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/merchants/data/merchant_catalog.dart';
import 'package:outflow/features/merchants/domain/entities/merchant.dart';
import 'package:outflow/features/merchants/presentation/merchant_providers.dart';
import 'package:outflow/features/notifications/presentation/notification_providers.dart';
import 'package:outflow/features/subscriptions/domain/charge_pattern.dart';
import 'package:outflow/features/subscriptions/domain/entities/subscription.dart';
import 'package:outflow/features/subscriptions/presentation/subscription_providers.dart';
import 'package:outflow/features/subscriptions/presentation/widgets/subscription_editor_sheet.dart';

import 'support/fakes.dart';

void main() {
  final now = DateTime(2026, 10, 20, 9);
  final netflix = MerchantCatalog.all.firstWhere((m) => m.id == 'cat.netflix');

  Future<MemorySubscriptions> pump(WidgetTester tester, {Subscription? editing}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = MemorySubscriptions([?editing]);
    final container = ProviderContainer(overrides: [
      nowProvider.overrideWithValue(now),
      subscriptionRepositoryProvider.overrideWithValue(repo),
      merchantsProvider.overrideWith((ref) => Stream.value(MerchantCatalog.all)),
      requestNotificationPermissionProvider.overrideWithValue(() async => true),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSubscriptionEditor(context, merchant: netflix, editing: editing),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('alta: el importe con el teclado propio y "Se renueva el" como ancla', (tester) async {
    final repo = await pump(tester);
    expect(find.text('Se renueva el'), findsOneWidget);
    expect(find.text('Netflix'), findsWidgets);

    for (final k in ['2', '9', '.', '9', '0']) {
      await tester.tap(find.text(k).last);
    }
    await tester.pump();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final s = repo.saved.single;
    expect(s.price, const Money(2990, 'PEN'));
    expect(s.merchantId, 'cat.netflix');
    expect(s.firstChargeDate, DateTime(2026, 10, 21), reason: 'por defecto, mañana');
    expect(s.pattern, const ChargePattern.sameDay(21));
    expect(s.cycle, const BillingCycle.monthly());
  });

  testWidgets('editar sin tocar la fecha conserva ancla, historial y patrón', (tester) async {
    final existing = Subscription(
      id: 'nf',
      merchantId: 'cat.netflix',
      name: 'Netflix',
      price: const Money(2990, 'PEN'),
      cycle: const BillingCycle.monthly(),
      firstChargeDate: DateTime(2026, 11, 19),
      category: SpendCategory.streaming,
      paymentMethod: const PaymentMethod(kind: PaymentKind.card),
      createdAt: DateTime(2026, 1, 1),
      chargeHistory: [ChargeRecord(date: DateTime(2026, 10, 19), confirmed: true)],
      chargePattern: const ChargePattern.everyNDays(31),
    );
    final repo = await pump(tester, editing: existing);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    final s = repo.saved.single;
    expect(s.firstChargeDate, DateTime(2026, 11, 19));
    expect(s.chargeHistory, hasLength(1));
    expect(s.chargePattern, const ChargePattern.everyNDays(31));
    expect(s.price, const Money(2990, 'PEN'));
  });
}
