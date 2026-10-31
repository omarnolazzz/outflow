import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/widgets/outflow_mark.dart';
import 'package:outflow/features/account/presentation/welcome_screen.dart';

void main() {
  for (final size in const [Size(360, 640), Size(430, 932)]) {
    testWidgets('bienvenida: ilustración arriba y tarjeta con Google, sin desbordes a ${size.width}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: WelcomeScreen())));
      // La intro dura ~2 s; el resto anima en bucle, así que se avanza a mano.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Continuar con Google'), findsOneWidget);
      expect(find.byType(OutflowMark), findsOneWidget, reason: 'la intro terminó y solo queda la marca de la ilustración');
      expect(find.byType(Image), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
