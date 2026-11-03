import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/presentation/widgets/merchant_avatar.dart';
import '../../domain/category.dart';
import '../../domain/movement.dart';
import 'category_icon.dart';

/// Fila de un movimiento: icono (logo si es de suscripción), concepto, categoría
/// y el importe con signo (ingresos en verde). Transferencias y ajustes no tienen
/// categoría ([category] null) y llevan su propio icono.
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
    // Transferencias y ajustes no tienen categoría: los nombra su tipo.
    final kindName = switch (m.kind) {
      MovementKind.transfer => 'Transferencia',
      MovementKind.adjustment => 'Ajuste de saldo',
      _ => null,
    };
    final title = m.title.isNotEmpty ? m.title : (kindName ?? category?.name ?? 'Movimiento');
    final subtitle = [
      if (kindName == null) category?.name ?? '' else if (kindName != title) kindName,
      if (showDate) Fmt.dateShort(m.date),
      if (m.provisional) 'previsto',
      if (!m.countsInWallet && !m.isTransferOrAdjustment) 'no descuenta',
    ].where((x) => x.isNotEmpty).join(' · ');
    final amount = '${_sign(m)}${Fmt.money(m.amount)}';

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
            else if (m.isTransferOrAdjustment)
              _KindBadge(m.kind == MovementKind.transfer ? LucideIcons.arrowLeftRight : LucideIcons.scale)
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
              style: AppType.amount.copyWith(
                color: !m.countsInWallet
                    ? AppColors.inkTertiary
                    : m.isExpense
                        ? AppColors.ink
                        : AppColors.income,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Una transferencia entre dos cuentas conocidas no tiene signo: no entra ni
  /// sale dinero. Con el otro lado desconocido, lo lleva según su sentido.
  static String _sign(Movement m) => switch (m.kind) {
        MovementKind.expense => '−',
        MovementKind.income => '+',
        MovementKind.adjustment => (m.adjustmentMinor ?? 0) < 0 ? '−' : '+',
        MovementKind.transfer => m.toAccountId != null ? '' : (m.transferIncoming ? '+' : '−'),
      };
}

/// Círculo neutro con el icono de una transferencia o un ajuste.
class _KindBadge extends StatelessWidget {
  const _KindBadge(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(color: AppColors.fill, shape: BoxShape.circle),
        child: Icon(icon, size: 19, color: AppColors.inkSecondary),
      );
}
