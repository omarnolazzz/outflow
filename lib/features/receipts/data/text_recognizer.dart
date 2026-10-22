import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// No se pudo leer el texto de la foto.
class TextRecognitionFailed implements Exception {
  const TextRecognitionFailed([this.message = '']);
  final String message;
}

/// Lee el texto de una foto (en el dispositivo; la foto no sale de él).
abstract interface class TextRecognizer {
  Future<String> recognize(String imagePath);
}

/// Reconocimiento de texto de iOS (Vision) por un canal propio
/// (`ios/Runner/TextRecognitionPlugin.swift`).
class ChannelTextRecognizer implements TextRecognizer {
  const ChannelTextRecognizer();

  static const _channel = MethodChannel('outflow/ocr');

  @override
  Future<String> recognize(String imagePath) async {
    try {
      return await _channel.invokeMethod<String>('recognizeText', {'path': imagePath}) ?? '';
    } on PlatformException catch (e) {
      throw TextRecognitionFailed(e.message ?? e.code);
    } on MissingPluginException {
      throw const TextRecognitionFailed('Lectura no disponible en este dispositivo.');
    }
  }
}

/// Vista previa web: devuelve un ticket de ejemplo para probar el flujo.
class SampleTextRecognizer implements TextRecognizer {
  const SampleTextRecognizer();

  @override
  Future<String> recognize(String imagePath) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return 'BODEGA SAN MARTIN S.A.C.\nRUC 20512345678\nFECHA: 20/10/2026\n'
        '2 GASEOSA 500ML 7.00\n1 PAN DE MOLDE 8.50\n1 LECHE GLORIA 4.90\n3 GALLETAS 25.50\n'
        'SUBTOTAL 45.90\nTOTAL S/ 45.90';
  }
}

final textRecognizerProvider = Provider<TextRecognizer>(
  (ref) => kIsWeb ? const SampleTextRecognizer() : const ChannelTextRecognizer(),
);
