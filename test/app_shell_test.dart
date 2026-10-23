import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/shell/presentation/app_shell.dart';

/// Página con un contador: si el estado sobrevive al cambiar de pestaña, el número se conserva.
class _Counter extends StatefulWidget {
  const _Counter(this.name);
  final String name;
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(onPressed: () => setState(() => n++), child: Text('${widget.name} $n')),
      );
}

void main() {
  final actions = <String>[];

  Widget app() => MaterialApp(
        home: AppShell(
          pages: {for (final t in AppTab.values) t: (_) => _Counter(t.name)},
          onQuickAdd: (a) => actions.add(a.name),
        ),
      );

  setUp(actions.clear);

  testWidgets('cambiar de pestaña muestra su página y conserva el estado de las demás', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('home 0'));
    await tester.pump();
    expect(find.text('home 1'), findsOneWidget);

    await tester.tap(find.text('Movimientos'));
    await tester.pumpAndSettle();
    expect(find.text('movements 0'), findsOneWidget);
    expect(find.text('home 1'), findsNothing);

    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    expect(find.text('home 1'), findsOneWidget);
  });

  testWidgets('las 5 pestañas tienen su etiqueta y caben a 360 px de ancho', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    for (final label in ['Inicio', 'Movimientos', 'Suscripciones', 'Amigos', 'Resumen']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(AppTab.values.length, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"+" despliega Gasto, Ingreso y Suscripción; un segundo toque las cierra', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Gasto'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Añadir'));
    await tester.pumpAndSettle();
    expect(find.text('Gasto'), findsOneWidget);
    expect(find.text('Ingreso'), findsOneWidget);
    expect(find.text('Suscripción'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Añadir'));
    await tester.pumpAndSettle();
    expect(find.text('Gasto'), findsNothing);
  });

  testWidgets('elegir una acción la ejecuta y cierra el menú', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Añadir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ingreso'));
    await tester.pumpAndSettle();
    expect(actions, ['income']);
    expect(find.text('Gasto'), findsNothing);
  });
}
