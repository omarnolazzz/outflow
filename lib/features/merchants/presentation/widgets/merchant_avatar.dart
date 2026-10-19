import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../domain/entities/merchant.dart';

/// Icono de página estilo Notion: emoji, icono lineal, imagen local o iniciales,
/// siempre sobre el mismo cuadrado con borde para que la lista quede alineada.
class MerchantAvatar extends StatelessWidget {
  const MerchantAvatar({super.key, required this.logo, required this.name, this.size = 36});

  final MerchantLogo logo;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.22);
    final Widget inner = switch (logo.kind) {
      LogoKind.emoji => Text(logo.value, style: TextStyle(fontSize: size * 0.52, height: 1)),
      LogoKind.icon => Icon(kLineIcons[logo.value] ?? Icons.circle_outlined,
          size: size * 0.5, color: AppColors.ink),
      LogoKind.file => ClipRRect(
          borderRadius: radius,
          child: Image.file(
            File(logo.value),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _Monogram(name: name, size: size),
          ),
        ),
      LogoKind.monogram => _Monogram(name: name, size: size),
    };

    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: radius,
          border: Border.all(color: AppColors.border),
        ),
        child: inner,
      ),
    );
  }
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
