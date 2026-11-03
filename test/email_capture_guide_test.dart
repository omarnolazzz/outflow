import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/features/capture/data/capture_inbox.dart';
import 'package:outflow/features/capture/data/capture_key.dart';
import 'package:outflow/features/capture/data/capture_sources_repository.dart';
import 'package:outflow/features/capture/presentation/capture_link_handler.dart';
import 'package:outflow/features/friends/data/social_repository.dart';
import 'package:outflow/features/friends/presentation/friends_providers.dart';
import 'package:outflow/features/settings/presentation/email_capture_guide_screen.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';

class _Secure implements FlutterSecureStorage {
  final values = <String, String>{'outflow.capture.key': 'clave-de-prueba'};

  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      values[key];

  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    values[key] = value!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sources implements CaptureSourcesRepository {
  final map = <String, String>{};

  @override
  Map<String, String> read() => map;

  @override
  Future<void> assign(String sourceKey, String accountId) async => map[sourceKey] = accountId;
}

CaptureEvent _event(String text) =>
    CaptureEvent(sourceKey: 'email:prueba', sourceLabel: 'Prueba', text: text, receivedAt: DateTime(2026, 10, 22, 13));

void main() {
  late _Sources sources;
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    sources = _Sources();
    final movements = MemoryMovements();
    // El hijo de este botón empuja la guía para poder salir de ella.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(_Secure()),
        captureSourcesRepositoryProvider.overrideWithValue(sources),
        nowProvider.overrideWithValue(DateTime(2026, 10, 22, 13)),
        movementRepositoryProvider.overrideWithValue(movements),
        accountRepositoryProvider.overrideWithValue(MemoryAccounts([newDefaultAccount('PEN')], movements)),
        socialRepositoryProvider.overrideWithValue(const UnavailableSocialRepository()),
        walletSettingsRepositoryProvider.overrideWithValue(MemorySettings()),
        categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EmailCaptureGuideScreen())),
                child: const Text('abrir guía'),
              ),
            );
          },
        ),
      ),
    ));
    await tester.tap(find.text('abrir guía'));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
  }

  testWidgets('explica los pasos, la codificación y que la app se abre un momento', (tester) async {
    await pump(tester);
    expect(find.text('Captura por correo'), findsOneWidget);
    expect(find.textContaining('Ajustes'), findsWidgets);
    expect(find.textContaining('soporte@lemon.me'), findsWidgets);
    expect(find.textContaining('Codificar URL'), findsWidgets);
    expect(find.textContaining('se abre un momento'), findsWidgets);
  });

  testWidgets('la URL lleva la clave de la instalación y Copiar la deja en el portapapeles', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await pump(tester);
    await reveal(tester, find.text('Copiar'));
    await tester.tap(find.text('Copiar'));
    await tester.pump();
    expect(copied, startsWith('outflow://captura?clave=clave-de-prueba&fuente='));
    expect(copied, contains('&texto='));
  });

  testWidgets('Probar sin nada recibido lo explica', (tester) async {
    await pump(tester);
    await reveal(tester, find.text('Probar'));
    await tester.tap(find.text('Probar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Todavía no ha llegado'), findsOneWidget);
  });

  testWidgets('Probar con un ejemplo muestra lo que se entendió', (tester) async {
    await pump(tester);
    await reveal(tester, find.text('Probar con un ejemplo'));
    await tester.tap(find.text('Probar con un ejemplo'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Lo que se entendió'));
    expect(find.textContaining(RegExp(r'45[.,]50')), findsWidgets);
    expect(find.textContaining('BODEGA EJEMPLO'), findsWidgets);
    expect(find.textContaining('99887766'), findsWidgets);
  });

  testWidgets('Probar con un texto recibido sin importe dice que no se reconoció', (tester) async {
    await pump(tester);
    container.read(lastCaptureProvider.notifier).set(_event('Hola, bienvenido a tu banco'));
    await reveal(tester, find.text('Probar'));
    await tester.tap(find.text('Probar'));
    await tester.pumpAndSettle();
    expect(find.text('No se reconoció ningún importe'), findsOneWidget);
  });

  testWidgets('al salir de la guía se borra el último texto', (tester) async {
    await pump(tester);
    container.read(lastCaptureProvider.notifier).set(_event(kCaptureSampleText));
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(container.read(lastCaptureProvider), isNull);
  });

  testWidgets('la cuenta de una fuente se elige en la guía', (tester) async {
    await pump(tester);
    await reveal(tester, find.byKey(const ValueKey('sourceName')));
    await tester.enterText(find.byKey(const ValueKey('sourceName')), 'Scotiabank');
    await tester.tap(find.text('Añadir fuente'));
    await tester.pumpAndSettle();
    expect(sources.map.keys, contains('email:scotiabank'));
    expect(find.text('Scotiabank'), findsWidgets);
  });
}
