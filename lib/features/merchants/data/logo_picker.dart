import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../domain/entities/merchant.dart';

enum LogoSource { photos, files }

/// Elige una imagen (Fotos o Archivos) y la convierte en un logo listo para guardar.
abstract final class LogoPicker {
  /// Lado del PNG guardado: nítido en el avatar más grande (56 pt @3x ≈ 168 px).
  static const size = 256;

  static const extensions = ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'ico'];

  /// `null` si el usuario cancela. Lanza [LogoImageException] si no se puede leer.
  static Future<MerchantLogo?> pick(LogoSource source) async {
    final file = await FilePicker.pickFile(
      type: source == LogoSource.photos ? FileType.image : FileType.custom,
      allowedExtensions: source == LogoSource.files ? extensions : null,
      // Fotos de iPhone en HEIC → JPEG compatible, que sí se puede decodificar.
      darwinOptions: const DarwinOptions(
        assetRepresentationMode: DarwinAssetRepresentationMode.compatible,
      ),
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final png = await compute(squarePng, bytes);
    return MerchantLogo.image(base64Encode(png));
  }

  /// Decodifica cualquier formato soportado (PNG, JPG, WebP, GIF, BMP, ICO…),
  /// recorta el centro a cuadrado y lo reduce a [size] px.
  @visibleForTesting
  static Uint8List squarePng(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw const LogoImageException();
    final side = math.min(decoded.width, decoded.height);
    final square = img.copyCrop(
      decoded,
      x: (decoded.width - side) ~/ 2,
      y: (decoded.height - side) ~/ 2,
      width: side,
      height: side,
    );
    final resized = side > size
        ? img.copyResize(square, width: size, height: size, interpolation: img.Interpolation.average)
        : square;
    return img.encodePng(resized, level: 6);
  }
}

class LogoImageException implements Exception {
  const LogoImageException();
  @override
  String toString() => 'No se pudo leer la imagen';
}
