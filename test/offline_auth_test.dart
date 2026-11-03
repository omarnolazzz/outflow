import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/account/data/firebase_auth_service.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/domain/auth_service.dart';
import 'package:outflow/features/account/presentation/lock_screen.dart';
import 'package:outflow/features/account/presentation/login_hero.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/core/widgets/outflow_mark.dart';

/// Los logos animan en bucle: se avanza a mano hasta pasar la intro.
Future<void> settleIntro(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Bio implements Biometrics {
  int calls = 0;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<String> label() async => 'Face ID';
  @override
  Future<bool> authenticate(String reason) async {
    calls++;
    return true;
  }
}

void main() {
  test('sin conexión, "Continuar con Google" falla con AuthOffline sin abrir Google', () async {
    final service = FirebaseAuthService(online: () async => false);
    await expectLater(service.signInWithGoogle(), throwsA(isA<AuthOffline>()));
  });

  testWidgets('sin Face ID activado, el bloqueo ofrece siempre el bloqueo del teléfono', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    const account = Account(uid: 'u', email: 'g@example.com', displayName: 'Gabriel');
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: LockScreen(state: Locked(account))),
    ));
    await settleIntro(tester);
    expect(find.text('Usar el bloqueo del teléfono'), findsOneWidget);
    expect(find.textContaining('Desbloquear con'), findsNothing);
  });

  for (final size in const [Size(320, 568), Size(360, 640), Size(430, 932)]) {
    for (final faceId in const [true, false]) {
      testWidgets('bloqueo con logos y sin desbordes a ${size.width}x${size.height}, Face ID $faceId', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const account = Account(uid: 'u', email: 'gabrielnolazco@example.com', displayName: 'Gabriel');
        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(home: LockScreen(state: Locked(account, faceId: faceId))),
        ));
        await settleIntro(tester);
        expect(find.byType(LoginHero), findsOneWidget);
        expect(find.byType(OutflowMark), findsOneWidget);
        expect(find.text('Hola, Gabriel'), findsOneWidget);
        expect(find.text('Continuar con Google'), findsOneWidget);
        expect(find.text('Desbloquear con Face ID'), faceId ? findsOneWidget : findsNothing);
        if (size.height > 800) expect(find.byType(Image), findsWidgets, reason: 'logos de suscripciones');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('al abrir el bloqueo, Face ID no se dispara solo', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const account = Account(uid: 'u', email: 'g@example.com', displayName: 'Gabriel');
    final auth = _Bio();
    await tester.pumpWidget(ProviderScope(
      overrides: [biometricsProvider.overrideWithValue(auth)],
      child: const MaterialApp(home: LockScreen(state: Locked(account, faceId: true))),
    ));
    await settleIntro(tester);
    expect(auth.calls, 0);
  });
}
