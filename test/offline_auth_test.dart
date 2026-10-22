import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/account/data/firebase_auth_service.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/domain/auth_service.dart';
import 'package:outflow/features/account/presentation/lock_screen.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';

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
    await tester.pumpAndSettle();
    expect(find.text('Usar el bloqueo del teléfono'), findsOneWidget);
    expect(find.textContaining('Desbloquear con'), findsNothing);
  });
}
