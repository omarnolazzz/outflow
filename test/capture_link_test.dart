import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/features/capture/data/capture_inbox.dart';
import 'package:outflow/features/capture/data/capture_key.dart';
import 'package:outflow/features/capture/domain/capture_link.dart';
import 'package:outflow/features/capture/domain/parse_bank_text.dart';
import 'package:outflow/features/capture/presentation/capture_link_handler.dart';
import 'package:outflow/features/capture/presentation/capture_providers.dart';

class _Secure implements FlutterSecureStorage {
  final values = <String, String>{};

  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      values[key];

  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    values.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Runner implements CaptureRunner {
  int runs = 0;

  @override
  Future<void> run() async => runs++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  keyConcurrencyTests();
  final now = DateTime(2026, 10, 22, 13);
  const key = 'k-secreta-123';
  Uri link({String? clave = key, String fuente = 'Scotiabank', String texto = 'Consumo de S/ 10.00'}) => Uri(
        scheme: 'outflow',
        host: 'captura',
        queryParameters: {'clave': ?clave, 'fuente': fuente, 'texto': texto},
      );

  group('parseCaptureLink', () {
    test('con la clave correcta devuelve el evento', () {
      final e = parseCaptureLink(link(), expectedKey: key, now: now)!;
      expect(e.sourceKey, 'email:scotiabank');
      expect(e.sourceLabel, 'Scotiabank');
      expect(e.text, 'Consumo de S/ 10.00');
      expect(e.receivedAt, now);
    });

    test('sin clave o con clave errónea no devuelve nada', () {
      expect(parseCaptureLink(link(clave: null), expectedKey: key, now: now), isNull);
      expect(parseCaptureLink(link(clave: 'otra'), expectedKey: key, now: now), isNull);
      expect(parseCaptureLink(link(clave: ''), expectedKey: key, now: now), isNull);
      expect(parseCaptureLink(link(clave: '$key '), expectedKey: key, now: now), isNotNull,
          reason: 'un espacio sobrante del atajo no invalida la clave');
    });

    test('una clave esperada vacía nunca acepta nada', () {
      expect(parseCaptureLink(link(clave: ''), expectedKey: '', now: now), isNull);
      expect(parseCaptureLink(link(clave: null), expectedKey: '', now: now), isNull);
    });

    test('el texto se corta a 4000 caracteres', () {
      final e = parseCaptureLink(link(texto: 'a' * 5000), expectedKey: key, now: now)!;
      expect(e.text.length, 4000);
    });

    test('un texto vacío no es un evento', () {
      expect(parseCaptureLink(link(texto: '  '), expectedKey: key, now: now), isNull);
    });

    test('la fuente se normaliza y se limita', () {
      final e = parseCaptureLink(link(fuente: '  Dale   PERÚ  '), expectedKey: key, now: now)!;
      expect(e.sourceKey, 'email:dale perú');
      expect(e.sourceLabel, 'Dale PERÚ');
      final long = parseCaptureLink(link(fuente: 'x' * 200), expectedKey: key, now: now)!;
      expect(long.sourceLabel.length, lessThanOrEqualTo(40));
      final none = parseCaptureLink(link(fuente: ' '), expectedKey: key, now: now)!;
      expect(none.sourceKey, 'email:correo');
    });

    test('otros enlaces no son capturas', () {
      expect(parseCaptureLink(Uri.parse('outflow://gasto?clave=$key&texto=x'), expectedKey: key, now: now), isNull);
      expect(parseCaptureLink(Uri.parse('https://captura?clave=$key&texto=x'), expectedKey: key, now: now), isNull);
    });
  });

  group('clave por instalación', () {
    test('se crea una vez, se guarda en secure storage y no se repite', () async {
      final secure = _Secure();
      final a = await CaptureKeyStore(secure).key();
      final b = await CaptureKeyStore(secure).key();
      expect(a, isNotEmpty);
      expect(a.length, greaterThanOrEqualTo(32));
      expect(b, a);
      expect(secure.values['outflow.capture.key'], a);
      expect(await CaptureKeyStore(_Secure()).key(), isNot(a));
    });

    test('reset borra la clave y la siguiente es otra', () async {
      final secure = _Secure();
      final store = CaptureKeyStore(secure);
      final a = await store.key();
      await store.reset();
      expect(secure.values, isEmpty);
      expect(await store.key(), isNot(a));
    });
  });

  group('CaptureLinkHandler', () {
    late Directory dir;
    late _Runner runner;
    late ProviderContainer container;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('outflow_link');
      runner = _Runner();
      final secure = _Secure()..values['outflow.capture.key'] = key;
      container = ProviderContainer(overrides: [
        secureStorageProvider.overrideWithValue(secure),
        captureInboxProvider.overrideWithValue(CaptureInbox(directory: () async => dir)),
        captureRunnerProvider.overrideWithValue(runner),
      ]);
    });

    tearDown(() {
      container.dispose();
      dir.deleteSync(recursive: true);
    });

    test('sin clave o con clave errónea no escribe en la bandeja ni procesa ni guarda texto', () async {
      final handler = container.read(captureLinkHandlerProvider);
      expect(await handler.handle(link(clave: null)), isFalse);
      expect(await handler.handle(link(clave: 'mala')), isFalse);
      expect(await container.read(captureInboxProvider).pending(), isEmpty);
      expect(runner.runs, 0);
      expect(container.read(lastCaptureProvider), isNull);
    });

    test('con la clave correcta entra en la bandeja, se procesa y queda para el diagnóstico', () async {
      final handler = container.read(captureLinkHandlerProvider);
      expect(await handler.handle(link()), isTrue);
      final pending = await container.read(captureInboxProvider).pending();
      expect(pending.single.text, 'Consumo de S/ 10.00');
      expect(runner.runs, 1);
      expect(container.read(lastCaptureProvider)!.text, 'Consumo de S/ 10.00');
    });

    test('otros hosts no son de la captura', () async {
      final handler = container.read(captureLinkHandlerProvider);
      expect(await handler.handle(Uri.parse('outflow://gasto?importe=1')), isFalse);
    });
  });

  test('el ejemplo de la guía se entiende', () {
    final parsed = parseBankText(kCaptureSampleText, fallbackCurrency: 'PEN', now: now)!;
    expect(parsed.amountMinor, 4550);
    expect(parsed.direction, CaptureDirection.out);
    expect(parsed.operationId, isNotNull);
  });
}

void keyConcurrencyTests() {
  test('llamadas simultáneas a key() comparten una sola clave', () async {
    final secure = _Secure();
    final store = CaptureKeyStore(secure);
    final keys = await Future.wait([store.key(), store.key(), store.key()]);
    expect(keys.toSet(), hasLength(1));
    expect(secure.values['outflow.capture.key'], keys.first);
  });
}
