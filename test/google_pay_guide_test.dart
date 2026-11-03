import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/capture/data/capture_sources_repository.dart';
import 'package:outflow/features/settings/presentation/google_pay_guide_screen.dart';
import 'package:outflow/features/wallet/data/payment_listener.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

class _FakeListener implements PaymentListener {
  _FakeListener(this.enabled, {this.apps = const [], Set<String>? on}) : on = on ?? {};
  bool enabled;
  final List<CaptureApp> apps;
  final Set<String> on;
  int opened = 0;
  final calls = <String>[];

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> openSettings() async => opened++;

  @override
  Future<List<CaptureApp>> seenApps() async => apps;

  @override
  Future<Set<String>> enabledApps() async => {...on};

  @override
  Future<void> setEnabled(String package, bool value) async {
    calls.add('$package:$value');
    value ? on.add(package) : on.remove(package);
  }
}

class _FakeSources implements CaptureSourcesRepository {
  final map = <String, String>{};

  @override
  Map<String, String> read() => Map.of(map);

  @override
  Future<void> assign(String sourceKey, String accountId) async => map[sourceKey] = accountId;
}

WalletAccount _account(String id, String name) => WalletAccount(
      id: id,
      name: name,
      type: AccountType.bank,
      currency: 'PEN',
      initialMinor: 0,
      initialDate: DateTime(2026),
      isDefault: id == 'default',
    );

void main() {
  const bcp = CaptureApp(package: 'com.bcp.bank.bcp', label: 'BCP');
  const dale = CaptureApp(package: 'pe.dale.app', label: 'Dale');

  Future<void> pump(WidgetTester tester, _FakeListener listener, [_FakeSources? sources]) async {
    tester.view.physicalSize = const Size(1170, 5000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        paymentListenerProvider.overrideWithValue(listener),
        captureSourcesRepositoryProvider.overrideWithValue(sources ?? _FakeSources()),
        accountsProvider.overrideWith((ref) => Stream.value([_account('default', 'Efectivo'), _account('bbva', 'BBVA ahorros')])),
      ],
      child: const MaterialApp(home: GooglePayGuideScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('sin permiso ofrece activarlo y abre los ajustes del teléfono', (tester) async {
    final listener = _FakeListener(false);
    await pump(tester, listener);
    expect(find.text('Captura automática'), findsOneWidget);
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

  testWidgets('activar una app vista llama a setEnabled', (tester) async {
    final listener = _FakeListener(true, apps: [bcp, dale], on: {bcp.package});
    await pump(tester, listener);
    expect(find.text('Dale'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('switch:pe.dale.app')));
    await tester.pumpAndSettle();
    expect(listener.calls, ['pe.dale.app:true']);
    expect(listener.on, contains('pe.dale.app'));
  });

  testWidgets('elegir cuenta para una app activada la guarda', (tester) async {
    final sources = _FakeSources();
    await pump(tester, _FakeListener(true, apps: [bcp], on: {bcp.package}), sources);
    await tester.tap(find.byKey(const ValueKey('account:com.bcp.bank.bcp')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('BBVA ahorros').last);
    await tester.pumpAndSettle();
    expect(sources.map, {'com.bcp.bank.bcp': 'bbva'});
  });
}
