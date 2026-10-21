import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'pressable.dart';

enum PillTone { neutral, accent, danger, strong }

/// Etiqueta corta de estado ("Hoy", "en 2 días", "Pagado").
class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.tone = PillTone.neutral, this.icon});

  final String text;
  final PillTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      PillTone.neutral => (AppColors.fill, AppColors.inkSecondary),
      PillTone.accent => (AppColors.accentSoft, AppColors.accent),
      PillTone.danger => (AppColors.dangerSoft, AppColors.danger),
      PillTone.strong => (AppColors.ink, AppColors.onAccent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Text(text, style: AppType.caption.copyWith(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Botón compacto en cápsula para acciones dentro de tarjetas.
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, required this.onTap, this.filled = false, this.icon});

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.onAccent : AppColors.ink;
    return Pressable(
      onTap: onTap,
      haptic: true,
      highlight: false,
      scale: 0.94,
      borderRadius: BorderRadius.circular(20),
      semanticLabel: label,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: ShapeDecoration(
          color: filled ? AppColors.accent : AppColors.fill,
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.subhead.copyWith(color: fg, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Título de sección con acción opcional a la derecha ("Ver todos").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
        child: Row(
          children: [
            Expanded(child: Text(title, style: AppType.title2)),
            if (action != null)
              Pressable(
                onTap: onAction,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(action!, style: AppType.subhead.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      );
}
