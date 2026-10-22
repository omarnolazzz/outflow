import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/receipts/data/text_recognizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('outflow/ocr');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('envía la ruta de la foto y devuelve el texto leído', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return 'TOTAL S/ 45.90';
    });
    final text = await const ChannelTextRecognizer().recognize('/tmp/ticket.jpg');
    expect(text, 'TOTAL S/ 45.90');
    expect(received?.method, 'recognizeText');
    expect(received?.arguments, {'path': '/tmp/ticket.jpg'});
  });

  test('un error del lado nativo se convierte en TextRecognitionFailed', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'vision'));
    await expectLater(const ChannelTextRecognizer().recognize('/tmp/x.jpg'), throwsA(isA<TextRecognitionFailed>()));
  });
}
