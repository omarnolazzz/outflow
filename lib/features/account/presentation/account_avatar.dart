import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/account.dart';

/// Foto de la cuenta de Google (o la inicial si no hay foto o no carga).
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.account, this.size = 40});

  final Account account;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
      child: Text(
        account.firstName.isEmpty ? '?' : account.firstName[0].toUpperCase(),
        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w600, color: AppColors.accent),
      ),
    );
    final url = account.photoUrl;
    if (url == null) return initial;
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => initial,
        frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : initial,
      ),
    );
  }
}

/// "G" de Google para el botón de acceso (dibujada, sin recursos de marca).
class GoogleGlyph extends StatelessWidget {
  const GoogleGlyph({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
        child: Text(
          'G',
          style: TextStyle(fontSize: size * 0.72, fontWeight: FontWeight.w700, color: const Color(0xFF4285F4)),
        ),
      );
}
