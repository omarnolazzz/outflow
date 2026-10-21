import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/account/presentation/splash_intro.dart';

void main() {
  Widget host({required GlobalKey target, required bool ready, required List<String> log}) =>
      MaterialApp(
        home: Stack(
          children: [
            Positioned(left: 20, top: 100, child: SizedBox.square(key: target, dimension: 56)),
            Positioned.fill(
              child: SplashIntro(
                target: target,
                ready: ready,
                onReveal: () => log.add('reveal'),
                onDone: () => log.add('done'),
              ),
            ),
          ],
        ),
      );

  testWidgets('espera al destino y luego revela y termina', (tester) async {
    final target = GlobalKey();
    final log = <String>[];

    await tester.pumpWidget(host(target: target, ready: false, log: log));
    await tester.pump(const Duration(seconds: 3));
    expect(log, isEmpty, reason: 'sin destino, la intro se queda en la pausa');

    await tester.pumpWidget(host(target: target, ready: true, log: log));
    await tester.pumpAndSettle();
    expect(log, ['reveal', 'done']);
  });
}
