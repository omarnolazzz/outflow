import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/cloud/presentation/cloud_banner.dart';
import 'package:outflow/features/cloud/presentation/cloud_choice_sheet.dart';
import 'package:outflow/features/cloud/presentation/cloud_sync.dart';

const _title = 'Este teléfono tiene datos que no están en tu cuenta';
const _bannerText = 'Tu información aún no se está guardando en la nube';

class _FakeCloud extends CloudSync {
  _FakeCloud(this.initial, this.log);
  final CloudSyncState initial;
  final List<String> log;
  @override
  CloudSyncState build() => initial;
  void emit(CloudSyncState s) => state = s;
  @override
  Future<void> chooseMerge() async => log.add('merge');
  @override
  Future<void> chooseCloudOnly() async => log.add('cloudOnly');
  @override
  Future<void> retry() async => log.add('retry');
}

class _FakeSession extends SessionController {
  _FakeSession(this.initial);
  final SessionState initial;
  @override
  SessionState build() => initial;
  void emit(SessionState s) => state = s;
}

const _account = Account(uid: 'u', email: 'g@example.com', displayName: 'Gabriel');

void main() {
  late List<String> log;
  late _FakeCloud cloud;
  late _FakeSession session;

  Future<void> pump(WidgetTester tester, CloudSyncState initial, {SessionState? sessionState}) async {
    tester.view.physicalSize = const Size(1080, 2400); // 360 px de ancho
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final nav = GlobalKey<NavigatorState>();
    log = [];
    cloud = _FakeCloud(initial, log);
    session = _FakeSession(sessionState ?? const Ready(_account));
    final container = ProviderContainer(overrides: [
      cloudSyncProvider.overrideWith(() => cloud),
      sessionControllerProvider.overrideWith(() => session),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: SafeArea(child: CloudBanner())),
        builder: (context, child) => CloudChoiceTrigger(navigator: nav, child: child!),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openChoice(WidgetTester tester) async {
    await pump(tester, CloudSyncState.syncing);
    cloud.emit(CloudSyncState.needsChoice);
    await tester.pumpAndSettle();
  }

  group('hoja de elegir', () {
    testWidgets('se abre cuando el estado pasa a needsChoice, sin desbordes a 360 px', (tester) async {
      await pump(tester, CloudSyncState.syncing);
      expect(find.text(_title), findsNothing);
      cloud.emit(CloudSyncState.needsChoice);
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
      expect(find.text('Puedes unirlos con los de tu cuenta o quedarte solo con los de la nube.'), findsOneWidget);
      expect(find.text('Unir'), findsOneWidget);
      expect(find.text('Usar solo los de la nube'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no se cierra al tocar fuera ni al deslizar', (tester) async {
      await openChoice(tester);
      await tester.tapAt(const Offset(180, 10));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
      await tester.fling(find.text(_title), const Offset(0, 600), 2000);
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
    });

    testWidgets('con la sesión bloqueada espera a que se desbloquee', (tester) async {
      await pump(tester, CloudSyncState.syncing, sessionState: const SessionLoading());
      cloud.emit(CloudSyncState.needsChoice);
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
      session.emit(const Ready(_account));
      await tester.pumpAndSettle();
      expect(find.text(_title), findsOneWidget);
    });

    testWidgets('Unir llama a chooseMerge', (tester) async {
      await openChoice(tester);
      await tester.tap(find.text('Unir'));
      await tester.pump();
      expect(log, ['merge']);
    });

    testWidgets('mientras actúa muestra progreso, desactiva el otro botón y se cierra al quedar en vivo',
        (tester) async {
      await openChoice(tester);
      await tester.tap(find.text('Unir'));
      cloud.emit(CloudSyncState.syncing);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      await tester.tap(find.text('Usar solo los de la nube'));
      await tester.pump();
      expect(find.textContaining('No se puede deshacer'), findsNothing);
      cloud.emit(CloudSyncState.live);
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
    });

    testWidgets('si falla (unavailable) se cierra y entra el aviso', (tester) async {
      await openChoice(tester);
      cloud.emit(CloudSyncState.syncing);
      await tester.pump();
      cloud.emit(CloudSyncState.unavailable);
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
      expect(find.text(_bannerText), findsOneWidget);
    });

    testWidgets('"Usar solo los de la nube" pide confirmar y luego llama a chooseCloudOnly', (tester) async {
      await openChoice(tester);
      await tester.tap(find.text('Usar solo los de la nube'));
      await tester.pumpAndSettle();
      expect(log, isEmpty);
      expect(
        find.text('Se descartarán los datos de este teléfono que no estén en tu cuenta. No se puede deshacer.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(log, isEmpty);
      await tester.tap(find.text('Usar solo los de la nube'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar y usar la nube'));
      await tester.pump();
      expect(log, ['cloudOnly']);
    });
  });

  testWidgets('si pasa a live con el diálogo de confirmar abierto, se cierran ambos y se puede reabrir', (tester) async {
    await openChoice(tester);
    await tester.tap(find.text('Usar solo los de la nube'));
    await tester.pumpAndSettle();
    cloud.emit(CloudSyncState.live);
    await tester.pumpAndSettle();
    expect(find.text(_title), findsNothing);
    expect(find.textContaining('No se puede deshacer'), findsNothing);
    cloud.emit(CloudSyncState.needsChoice);
    await tester.pumpAndSettle();
    expect(find.text(_title), findsOneWidget);
  });

  testWidgets('con needsChoice ya presente al montar, la hoja se abre', (tester) async {
    await pump(tester, CloudSyncState.needsChoice);
    expect(find.text(_title), findsOneWidget);
  });

  group('aviso', () {
    testWidgets('en unavailable se ve y al tocarlo reintenta', (tester) async {
      await pump(tester, CloudSyncState.unavailable);
      expect(find.text(_bannerText), findsOneWidget);
      await tester.tap(find.text(_bannerText));
      await tester.pump();
      expect(log, ['retry']);
    });

    for (final s in [CloudSyncState.live, CloudSyncState.idle, CloudSyncState.syncing]) {
      testWidgets('en $s no se ve', (tester) async {
        await pump(tester, s);
        expect(find.text(_bannerText), findsNothing);
      });
    }
  });
}
