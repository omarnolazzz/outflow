import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/domain/auth_service.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/notifications/domain/notification_rule.dart';
import 'package:outflow/features/notifications/presentation/notification_providers.dart';
import 'package:outflow/features/settings/presentation/settings_screen.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';

class _Auth implements AuthService {
  @override
  Account? current = const Account(uid: 'u', email: 'g@example.com', displayName: 'Gabriel Nolazco');
  int signOuts = 0;
  @override
  Future<Account> signInWithGoogle() async => current!;
  @override
  Future<void> signOut() async {
    signOuts++;
    current = null;
  }
}

class _Bio implements Biometrics {
  @override
  Future<bool> authenticate(String reason) async => true;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<String> label() async => 'Face ID';
}

void main() {
  late _Auth auth;
  late MemorySettings settings;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    auth = _Auth();
    settings = MemorySettings(WalletSettings(onboardingDone: true, walletStartedAt: DateTime(2026, 10, 1)));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        biometricsProvider.overrideWithValue(_Bio()),
        walletSettingsRepositoryProvider.overrideWithValue(settings),
        hasExistingDataProvider.overrideWithValue(false),
        clearLegacyPinProvider.overrideWithValue(() async {}),
        globalRuleProvider.overrideWith((ref) => Stream.value(NotificationRule.defaults)),
        categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra la cuenta de Google', (tester) async {
    await pump(tester);
    expect(find.text('Gabriel Nolazco'), findsOneWidget);
    expect(find.text('g@example.com'), findsOneWidget);
  });

  testWidgets('apagar el sobrante lo guarda en los ajustes', (tester) async {
    await pump(tester);
    expect(settings.read().carryOver, isTrue);
    await tester.tap(find.byKey(const ValueKey('carryOver')));
    await tester.pumpAndSettle();
    expect(settings.read().carryOver, isFalse);
  });

  testWidgets('"Cerrar sesión" pide confirmación y cierra la sesión', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('Cerrar sesión'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(auth.signOuts, 0, reason: 'primero pregunta');
    await tester.tap(find.text('Cerrar sesión').last);
    await tester.pumpAndSettle();
    expect(auth.signOuts, 1);
  });
}
