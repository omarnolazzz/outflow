import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// El PDF está protegido y no se indicó contraseña.
class PdfPasswordRequired implements Exception {
  const PdfPasswordRequired();
}

/// La contraseña indicada no abre el PDF.
class PdfWrongPassword implements Exception {
  const PdfWrongPassword();
}

/// No se pudo leer el PDF.
class PdfReadFailed implements Exception {
  const PdfReadFailed();
}

/// Lee el texto de un PDF en el teléfono: ni el archivo ni la contraseña salen de él.
abstract interface class PdfTextReader {
  Future<String> read(String path, {String? password});
}

/// PDFKit en iOS (`ios/Runner/PdfTextPlugin.swift`) y PdfBox en Android
/// (`MainActivity.kt`), por el canal `outflow/pdf`. La contraseña no se registra.
class ChannelPdfTextReader implements PdfTextReader {
  const ChannelPdfTextReader();

  static const _channel = MethodChannel('outflow/pdf');

  @override
  Future<String> read(String path, {String? password}) async {
    try {
      return await _channel.invokeMethod<String>('readText', {'path': path, 'password': password}) ?? '';
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'password_required' => const PdfPasswordRequired(),
        'wrong_password' => const PdfWrongPassword(),
        _ => const PdfReadFailed(),
      };
    } on MissingPluginException {
      throw const PdfReadFailed();
    }
  }
}

final pdfTextReaderProvider = Provider<PdfTextReader>((ref) => const ChannelPdfTextReader());
