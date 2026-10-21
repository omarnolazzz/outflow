import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/presentation/widgets/merchant_avatar.dart';
import '../../domain/category.dart';
import '../../domain/movement.dart';
import 'category_icon.dart';

/// Fila de un gasto o ingreso: icono (logo si es de suscripción), concepto,
/// categoría y el importe con signo (ingresos en verde).
class MovementRow extends StatelessWidget {
  const MovementRow({
    super.key,
    required this.movement,
    required this.category,
    this.merchant,
    this.onTap,
    this.showDate = false,
  });

  final Movement movement;
  final Category? category;

  /// Comercio de la suscripción que generó el cobro (para su logo).
  final Merchant? merchant;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final title = m.title.isNotEmpty ? m.title : (category?.name ?? 'Movimiento');
    final subtitle = [
      category?.name ?? '',
      if (showDate) Fmt.dateShort(m.date),
      if (m.provisional) 'previsto',
    ].where((x) => x.isNotEmpty).join(' · ');
    final amount = '${m.isExpense ? '−' : '+'}${Fmt.money(m.amount)}';

    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      semanticLabel: '$title, $amount',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (merchant != null)
              MerchantAvatar(logo: merchant!.logo, name: title, size: 40)
            else
              CategoryBadge(category: category),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppType.headline.copyWith(fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, style: AppType.footnote, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amount,
              style: AppType.amount.copyWith(color: m.isExpense ? AppColors.ink : AppColors.income),
            ),
          ],
        ),
      ),
    );
  }
}
