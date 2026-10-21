import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../domain/entities/merchant.dart';

/// Logo del comercio sobre un cuadrado redondeado con borde, para que la lista
/// quede alineada: logo oficial, imagen propia, emoji, icono lineal o iniciales.
///
/// Con [heroTag] el logo "viaja" entre pantallas (lista → detalle).
class MerchantAvatar extends StatelessWidget {
  const MerchantAvatar({
    super.key,
    required this.logo,
    required this.name,
    this.size = 36,
    this.heroTag,
  });

  final MerchantLogo logo;
  final String name;
  final double size;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.22);
    final monogram = _Monogram(name: name, size: size);
    // Decodifica al tamaño en pantalla: menos memoria y scroll más fluido.
    final cachePx = (size * MediaQuery.devicePixelRatioOf(context)).round();

    final Widget inner = switch (logo.kind) {
      LogoKind.emoji => Text(logo.value, style: TextStyle(fontSize: size * 0.52, height: 1)),
      LogoKind.icon => Icon(kLineIcons[logo.value] ?? Icons.circle_outlined,
          size: size * 0.5, color: AppColors.ink),
      LogoKind.asset => _FadeInImage(
          image: ResizeImage(AssetImage(logo.value), width: cachePx, height: cachePx),
          fallback: monogram,
        ),
      LogoKind.image => _FadeInImage(
          image: ResizeImage(MemoryImage(_LogoBytes.of(logo.value)), width: cachePx, height: cachePx),
          fallback: monogram,
        ),
      LogoKind.file => _FadeInImage(
          image: ResizeImage(FileImage(File(logo.value)), width: cachePx, height: cachePx),
          fallback: monogram,
        ),
      LogoKind.monogram => monogram,
    };

    final fullBleed = logo.kind == LogoKind.asset ||
        logo.kind == LogoKind.image ||
        logo.kind == LogoKind.file;

    Widget avatar = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fullBleed ? AppColors.background : AppColors.fill,
        borderRadius: radius,
      ),
      // El borde va por encima para que se vea también sobre logos blancos.
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: AppColors.separator),
      ),
      child: fullBleed
          ? ClipRRect(borderRadius: radius, child: SizedBox.expand(child: inner))
          : inner,
    );

    if (heroTag != null) {
      avatar = Hero(tag: heroTag!, child: avatar);
    }
    return ExcludeSemantics(child: avatar);
  }
}

/// Las imágenes propias llegan como base64: se decodifican una sola vez y se
/// reutiliza el mismo `Uint8List` para que `MemoryImage` acierte en caché
/// (si no, cada rebuild volvería a decodificar y parpadearía).
abstract final class _LogoBytes {
  static final _cache = <String, Uint8List>{};

  static Uint8List of(String base64) {
    final hit = _cache[base64];
    if (hit != null) return hit;
    if (_cache.length > 64) _cache.clear();
    return _cache[base64] = base64Decode(base64);
  }
}

/// Imagen que aparece con un fundido corto la primera vez que se decodifica
/// (las siguientes, ya en caché, se muestran al instante).
class _FadeInImage extends StatelessWidget {
  const _FadeInImage({required this.image, required this.fallback});
  final ImageProvider image;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => Image(
        image: image,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => Center(child: fallback),
        frameBuilder: (context, child, frame, sync) {
          if (sync) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: child,
          );
        },
      );
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letters = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
    final text = letters.map((w) => w.characters.first.toUpperCase()).join();
    return Text(
      text.isEmpty ? '?' : text,
      style: TextStyle(
        fontSize: size * 0.36,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: AppColors.ink,
      ),
    );
  }
}
