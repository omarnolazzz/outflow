import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/billing_cycle.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/merchants/data/merchant_catalog.dart';
import 'package:outflow/features/merchants/domain/entities/merchant.dart';
import 'package:outflow/features/merchants/presentation/merchant_providers.dart';
import 'package:outflow/features/notifications/domain/notification_rule.dart';
import 'package:outflow/features/notifications/presentation/notification_providers.dart';
import 'package:outflow/features/shell/presentation/app_shell.dart';
import 'package:outflow/features/subscriptions/domain/entities/subscription.dart';
import 'package:outflow/features/subscriptions/presentation/screens/subscription_detail_screen.dart';
import 'package:outflow/features/subscriptions/presentation/subscription_providers.dart';
import 'package:outflow/features/subscriptions/presentation/widgets/confirm_charge_sheet.dart';
import 'package:outflow/features/subscriptions/presentation/widgets/subscription_editor_sheet.dart';

import 'support/fakes.dart';

/// Lo abierto desde una pestaña debe quedar por encima de la barra de cristal,
/// no dentro del Navigator de la pestaña (que la barra tapa).
void main() {
  final now = DateTime(2026, 10, 20, 9);
  final netflixMerchant = MerchantCatalog.all.firstWhere((m) => m.id == 'cat.netflix');
  final netflix = Subscription(
    id: 'nf',
    merchantId: 'cat.netflix',
    name: 'Netflix',
    price: const Money(2990, 'PEN'),
    cycle: const BillingCycle.monthly(),
    firstChargeDate: DateTime(2026, 10, 18),
    category: SpendCategory.streaming,
    paymentMethod: const PaymentMethod(kind: PaymentKind.card),
    createdAt: DateTime(2026, 1, 1),
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nowProvider.overrideWithValue(now),
        subscriptionRepositoryProvider.overrideWithValue(MemorySubscriptions([netflix])),
        merchantsProvider.overrideWith((ref) => Stream.value(MerchantCatalog.all)),
        globalRuleProvider.overrideWith((ref) => Stream.value(NotificationRule.defaults)),
      ],
      child: MaterialApp(
        home: AppShell(
          onQuickAdd: (_) {},
          pages: {
            for (final t in AppTab.values)
              t: (_) => Consumer(
                    builder: (context, ref, _) => Column(
                      children: [
                        TextButton(onPressed: () => openSubscriptionDetail(context, 'nf'), child: Text('detalle ${t.name}')),
                        TextButton(
                          onPressed: () => showSubscriptionEditor(context, merchant: netflixMerchant),
                          child: Text('editor ${t.name}'),
                        ),
                        TextButton(
                          onPressed: () => showConfirmChargeSheet(context, ref, netflix, DateTime(2026, 10, 18)),
                          child: Text('confirmar ${t.name}'),
                        ),
                      ],
                    ),
                  ),
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder insideTab(Finder f) => find.ancestor(of: f, matching: find.byType(IndexedStack));

  testWidgets('el detalle se abre por encima de la barra', (tester) async {
    await pump(tester);
    await tester.tap(find.text('detalle home'));
    await tester.pumpAndSettle();
    expect(find.byType(SubscriptionDetailScreen), findsOneWidget);
    expect(insideTab(find.byType(SubscriptionDetailScreen)), findsNothing);
  });

  testWidgets('la hoja de suscripción se abre por encima de la barra', (tester) async {
    await pump(tester);
    await tester.tap(find.text('editor home'));
    await tester.pumpAndSettle();
    expect(find.byType(SubscriptionEditorSheet), findsOneWidget);
    expect(insideTab(find.byType(SubscriptionEditorSheet)), findsNothing);
  });

  testWidgets('editar desde el detalle también queda por encima', (tester) async {
    await pump(tester);
    await tester.tap(find.text('detalle home'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Editar'));
    await tester.pumpAndSettle();
    expect(find.byType(SubscriptionEditorSheet), findsOneWidget);
    expect(insideTab(find.byType(SubscriptionEditorSheet)), findsNothing);
  });

  testWidgets('la hoja de confirmar cobro se abre por encima de la barra', (tester) async {
    await pump(tester);
    await tester.tap(find.text('confirmar home'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar'), findsOneWidget);
    expect(insideTab(find.text('Confirmar')), findsNothing);
  });
}
