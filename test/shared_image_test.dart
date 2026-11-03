import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/receipts/data/shared_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('outflow/share');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('initialImage devuelve la ruta copiada a la caché', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => call.method == 'initialImage' ? '/cache/compartida_1.jpg' : null);
    expect(await ChannelSharedImageSource(channel).initialImage(), '/cache/compartida_1.jpg');
  });

  test('sin imagen compartida devuelve null', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await ChannelSharedImageSource(channel).initialImage(), isNull);
  });

  test('si la copia falló, lanza SharedImageFailed', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'copy'));
    expect(ChannelSharedImageSource(channel).initialImage(), throwsA(isA<SharedImageFailed>()));
  });

  test('en iPhone no hay canal y no pasa nada', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await ChannelSharedImageSource(channel).initialImage(), isNull);
  });

  test('las imágenes que llegan con la app abierta salen por el flujo', () async {
    final source = ChannelSharedImageSource(channel);
    final received = <String>[];
    final errors = <Object>[];
    final sub = source.images.listen(received.add, onError: errors.add);
    Future<void> native(String method, Object? args) => messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );
    await native('image', '/cache/compartida_2.jpg');
    await native('failed', null);
    await Future<void>.delayed(Duration.zero);
    expect(received, ['/cache/compartida_2.jpg']);
    expect(errors.single, isA<SharedImageFailed>());
    await sub.cancel();
  });
}
