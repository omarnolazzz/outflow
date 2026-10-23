import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:outflow/core/widgets/glass.dart';
import 'package:outflow/features/shell/presentation/app_shell.dart';

Widget _shell() => MaterialApp(
      home: AppShell(
        pages: {for (final t in AppTab.values) t: (_) => Center(child: Text(t.label))},
        onQuickAdd: (_) {},
      ),
    );

void main() {
  testWidgets('en iPhone la barra y el "+" son Liquid Glass', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(_shell());
      await tester.pump();
      expect(find.byType(LiquidGlassLayer), findsOneWidget);
      expect(find.byType(LiquidGlass), findsNWidgets(2));
      expect(find.byType(Glass), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('en Android se mantiene el cristal de siempre', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(_shell());
      await tester.pump();
      expect(find.byType(LiquidGlass), findsNothing);
      expect(find.byType(Glass), findsNWidgets(2));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
