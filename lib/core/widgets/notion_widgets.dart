import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'pressable.dart';

/// Etiqueta de sección ("Próximos cobros") con acción opcional a la derecha.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding});

  final String text;
  final Widget? trailing;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(20, 28, 20, 10),
        child: Row(
          children: [
            Expanded(child: Text(text, style: AppType.section)),
            ?trailing,
          ],
        ),
      );
}

enum TagTone { neutral, strong, danger }

/// Tag de Notion: píldora pequeña con fondo plano.
class NotionTag extends StatelessWidget {
  const NotionTag(this.label, {super.key, this.tone = TagTone.neutral, this.icon});

  final String label;
  final TagTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      TagTone.neutral => (AppColors.callout, AppColors.ink),
      TagTone.strong => (AppColors.ink, AppColors.onAccent),
      TagTone.danger => (AppColors.dangerSurface, AppColors.danger),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Text(
            label,
            style: AppType.caption.copyWith(color: fg, fontWeight: FontWeight.w500, height: 1.3),
          ),
        ],
      ),
    );
  }
}

/// Bloque con borde de 1px: la unidad visual de las tarjetas.
class NotionBlock extends StatelessWidget {
  const NotionBlock({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = AppColors.background,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

/// Fila de propiedad de página Notion: icono + etiqueta gris | valor.
class PropertyRow extends StatelessWidget {
  const PropertyRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Widget value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 148,
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.inkTertiary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label, style: AppType.body.copyWith(color: AppColors.inkSecondary)),
                ),
              ],
            ),
          ),
          Expanded(child: DefaultTextStyle.merge(style: AppType.body, child: value)),
        ],
      ),
    );
    return onTap == null ? row : Pressable(onTap: onTap, scale: 0.99, child: row);
  }
}

/// Callout de Notion: bloque gris con emoji para avisos contextuales.
class NotionCallout extends StatelessWidget {
  const NotionCallout({super.key, required this.emoji, required this.child, this.tone = TagTone.neutral});

  final String emoji;
  final Widget child;
  final TagTone tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: tone == TagTone.danger ? AppColors.dangerSurface : AppColors.callout,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18, height: 1.3)),
            const SizedBox(width: 10),
            Expanded(child: DefaultTextStyle.merge(style: AppType.body, child: child)),
          ],
        ),
      );
}

/// Botón de texto minimalista con borde (acciones secundarias).
class OutlineAction extends StatelessWidget {
  const OutlineAction({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool filled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.onAccent : (danger ? AppColors.danger : AppColors.ink);
    return Pressable(
      onTap: onTap,
      highlight: !filled,
      haptic: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? AppColors.accent : null,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: filled ? AppColors.accent : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 8)],
            Text(label, style: AppType.bodyStrong.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}
