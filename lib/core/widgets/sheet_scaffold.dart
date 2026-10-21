import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'pressable.dart';

/// Botón redondo de la cabecera (atrás, cerrar, menú).
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({super.key, required this.icon, required this.onTap, required this.label});

  final IconData icon;
  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        highlight: false,
        scale: 0.9,
        borderRadius: BorderRadius.circular(20),
        semanticLabel: label,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(color: AppColors.fill, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: AppColors.ink),
        ),
      );
}

/// Esqueleto de hoja/pantalla modal: cabecera (atrás · título · acción),
/// contenido desplazable y una zona [bottom] fija (botón Guardar, teclado).
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.bottom,
    this.onBack,
    this.closeIcon = false,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final Widget? bottom;
  final VoidCallback? onBack;

  /// "×" en lugar de "<" (hojas que se cierran hacia abajo).
  final bool closeIcon;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    CircleIconButton(
                      icon: closeIcon ? LucideIcons.x : LucideIcons.chevronLeft,
                      label: closeIcon ? 'Cerrar' : 'Atrás',
                      onTap: onBack ?? () => Navigator.maybePop(context),
                    ),
                    Expanded(
                      child: Text(title, textAlign: TextAlign.center, style: AppType.headline),
                    ),
                    trailing ?? const SizedBox(width: 40),
                  ],
                ),
              ),
              Expanded(child: child),
              if (bottom != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: bottom,
                ),
            ],
          ),
        ),
      );
}
