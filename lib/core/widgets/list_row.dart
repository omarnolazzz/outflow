import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'surface_card.dart';

/// Fila en tarjeta "Etiqueta ··· Valor" (Frecuencia · Mensual).
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.label,
    this.value,
    this.leading,
    this.trailing,
    this.onTap,
    this.valueColor,
  });

  final String label;
  final String? value;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        onTap: onTap,
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Text(label, style: AppType.body),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value ?? '',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.body.copyWith(color: valueColor ?? AppColors.inkSecondary),
              ),
            ),
            ?trailing,
            if (trailing == null && onTap != null) ...[
              const SizedBox(width: 6),
              const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.inkTertiary),
            ],
          ],
        ),
      );
}
