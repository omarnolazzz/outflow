import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/domain/auth_service.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/cloud/presentation/cloud_sync.dart';
import 'package:outflow/features/notifications/domain/notification_rule.dart';
import 'package:outflow/features/notifications/presentation/notification_providers.dart';
import 'package:outflow/features/settings/presentation/settings_screen.dart';
import 'package:outflow/features/statements/presentation/import_statement_screen.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
import 'package:outflow/features/wallet/presentation/screens/accounts_screen.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';

class _Auth implements AuthService {
  @override
  bool get verifiesIdentity => true;
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

class _StateCloud extends CloudSync {
  _StateCloud(this.initial, {this.migrated = false});
  final CloudSyncState initial;
  final bool migrated;
  @override
  Future<bool> willEraseCloud() async => migrated;
  @override
  CloudSyncState build() => initial;
}

void main() {
  late _Auth auth;
  late MemorySettings settings;
  late MemoryAccounts accounts;
  late MemoryMovements movements;

  Future<void> pump(WidgetTester tester, {List<Movement> existing = const [], CloudSyncState cloud = CloudSyncState.idle, bool migrated = false}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    auth = _Auth();
    movements = MemoryMovements(existing);
    accounts = MemoryAccounts([newDefaultAccount('PEN')], movements);
    settings = MemorySettings(WalletSettings(onboardingDone: true, walletStartedAt: DateTime(2026, 10, 1)));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        cloudSyncProvider.overrideWith(() => _StateCloud(cloud, migrated: migrated)),
        authServiceProvider.overrideWithValue(auth),
        biometricsProvider.overrideWithValue(_Bio()),
        walletSettingsRepositoryProvider.overrideWithValue(settings),
        accountRepositoryProvider.overrideWithValue(accounts),
        movementRepositoryProvider.overrideWithValue(movements),
        hasExistingDataProvider.overrideWithValue(false),
        clearLegacyPinProvider.overrideWithValue(() async {}),
        globalRuleProvider.overrideWith((ref) => Stream.value(NotificationRule.defaults)),
        categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
  }


  testWidgets('en iPhone, Ajustes ofrece la captura por correo', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await pump(tester);
    expect(find.text('Captura por correo', skipOffstage: false), findsOneWidget);
    expect(find.text('Registrar pagos con Apple Pay', skipOffstage: false), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('en Android, Ajustes no ofrece la captura por correo', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pump(tester);
    expect(find.text('Captura automática', skipOffstage: false), findsOneWidget);
    expect(find.text('Captura por correo', skipOffstage: false), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
  const cloudLine = 'También se borra la copia guardada en la nube.';
  const localFooter = 'Outflow · tus gastos se guardan cifrados en este teléfono';
  const cloudFooter = 'Tu información se guarda con tu cuenta de Google';

  Future<void> toFooter(WidgetTester tester) =>
      tester.drag(find.byType(Scrollable).first, const Offset(0, -3000)).then((_) => tester.pumpAndSettle());

  Future<void> openErase(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Borrar toda la información'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Borrar toda la información'));
    await tester.pumpAndSettle();
  }

  testWidgets('en vivo el pie habla de la cuenta de Google', (tester) async {
    await pump(tester, cloud: CloudSyncState.live, migrated: true);
    await toFooter(tester);
    expect(find.text(cloudFooter, skipOffstage: false), findsOneWidget);
    expect(find.text(localFooter, skipOffstage: false), findsNothing);
  });

  for (final s in [CloudSyncState.live, CloudSyncState.syncing, CloudSyncState.unavailable]) {
    testWidgets('migrada ($s), borrar avisa de la copia en la nube', (tester) async {
      await pump(tester, cloud: s, migrated: true);
      await openErase(tester);
      expect(find.textContaining(cloudLine), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final s in [CloudSyncState.idle, CloudSyncState.syncing, CloudSyncState.unavailable, CloudSyncState.needsChoice]) {
    testWidgets('sin migrar ($s), borrar no la menciona y el pie sigue local', (tester) async {
      await pump(tester, cloud: s);
      await toFooter(tester);
      expect(find.text(localFooter, skipOffstage: false), findsOneWidget);
      expect(find.text(cloudFooter, skipOffstage: false), findsNothing);
      await openErase(tester);
      expect(find.textContaining(cloudLine), findsNothing);
      expect(find.textContaining('No se puede deshacer'), findsOneWidget);
    });
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

  Future<void> pickCurrency(WidgetTester tester, String code) async {
    await tester.tap(find.text('Moneda principal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(code));
    await tester.pumpAndSettle();
  }

  testWidgets('la fila "Importar estado de cuenta" abre la importación', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Importar estado de cuenta'));
    await tester.pumpAndSettle();
    expect(find.byType(ImportStatementScreen), findsOneWidget);
  });

  testWidgets('la fila "Cuentas" abre la lista de cuentas', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Cuentas'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountsScreen), findsOneWidget);
  });

  group('cambiar la moneda principal', () {
    testWidgets('con la cuenta por defecto en otra moneda y sin movimientos, avisa y ofrece cambiarla', (tester) async {
      await pump(tester);
      await pickCurrency(tester, 'USD');
      expect(settings.read().currency, 'USD');
      expect(find.text('Tu cuenta sigue en PEN'), findsOneWidget);
      await tester.tap(find.text('Cambiar a USD'));
      await tester.pumpAndSettle();
      expect(accounts.saved.single.currency, 'USD');
      expect(accounts.saved.single.id, kDefaultAccountId);
    });

    testWidgets('con movimientos no la cambia: manda a crear una cuenta en la moneda nueva', (tester) async {
      await pump(tester, existing: [
        Movement(
          id: 'm',
          kind: MovementKind.income,
          amount: const Money(1000, 'PEN'),
          categoryId: 'salary',
          date: DateTime(2026, 10, 5),
          createdAt: DateTime(2026, 10, 5),
        ),
      ]);
      await pickCurrency(tester, 'USD');
      expect(find.text('Tu cuenta sigue en PEN'), findsOneWidget);
      expect(find.text('Cambiar a USD'), findsNothing);
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(accounts.saved.single.currency, 'PEN');
    });

    testWidgets('si la cuenta ya está en la moneda elegida no avisa', (tester) async {
      await pump(tester);
      await accounts.save(newDefaultAccount('USD'));
      await pickCurrency(tester, 'USD');
      expect(settings.read().currency, 'USD');
      expect(find.textContaining('Tu cuenta sigue'), findsNothing);
    });
  });
}
