import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:outflow/features/merchants/data/logo_picker.dart';
import 'package:outflow/features/merchants/data/merchant_catalog.dart';
import 'package:outflow/features/merchants/domain/entities/merchant.dart';

void main() {
  test('cada comercio del catálogo tiene su logo incluido en la app', () {
    for (final m in MerchantCatalog.all) {
      expect(m.logo.kind, LogoKind.asset, reason: m.name);
      expect(File(m.logo.value).existsSync(), isTrue, reason: '${m.name}: falta ${m.logo.value}');
    }
  });

  group('LogoPicker.squarePng', () {
    img.Image process(List<int> bytes) =>
        img.decodePng(LogoPicker.squarePng(Uint8List.fromList(bytes)))!;

    test('recorta el centro a cuadrado y reduce a 256 px', () {
      final wide = img.Image(width: 800, height: 400);
      final out = process(img.encodePng(wide));
      expect(out.width, LogoPicker.size);
      expect(out.height, LogoPicker.size);
    });

    test('no amplía imágenes pequeñas', () {
      final small = img.Image(width: 64, height: 80);
      final out = process(img.encodeJpg(small));
      expect(out.width, 64);
      expect(out.height, 64);
    });

    test('acepta .ico', () {
      final icon = img.Image(width: 48, height: 48);
      expect(process(img.encodeIco(icon)).width, 48);
    });

    test('un .ico con varios tamaños usa el más grande', () {
      final small = img.Image(width: 16, height: 16);
      final large = img.Image(width: 64, height: 64);
      final ico = img.IcoEncoder().encodeImages([small, large]);
      expect(process(ico).width, 64);
    });

    test('rechaza datos que no son imagen', () {
      expect(
        () => LogoPicker.squarePng(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<LogoImageException>()),
      );
    });
  });

  test('MerchantLogo de imagen sobrevive a JSON', () {
    const logo = MerchantLogo.image('iVBORw0KGgo=');
    expect(MerchantLogo.fromJson(logo.toJson()), logo);
  });
}
