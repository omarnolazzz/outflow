import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/notion_widgets.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/presentation/widgets/merchant_avatar.dart';
import '../../domain/entities/subscription.dart';

/// Tag compartido por la fila y el detalle para que el logo "viaje" entre ambos.
Object subscriptionLogoHeroTag(String subscriptionId) => 'logo-$subscriptionId';

/// Fila de "base de datos" Notion: icono · nombre/meta · monto/fecha.
class SubscriptionTile extends StatelessWidget {
  const SubscriptionTile({
    super.key,
    required this.subscription,
    required this.merchant,
    required this.now,
    required this.onTap,
  });

  final Subscription subscription;
  final Merchant? merchant;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = subscription;
    final next = s.nextCharge(now);
    final days = s.daysUntilCharge(now);
    final dimmed = !s.status.isBilling;

    final trailingCaption = switch (s.status) {
      SubscriptionStatus.paused => 'Pausada',
      SubscriptionStatus.cancelled => 'Cancelada',
      _ => days! <= 7 ? Fmt.relativeDays(days) : Fmt.dateShort(next!),
    };

    return Pressable(
      onTap: onTap,
      scale: 0.985,
      borderRadius: BorderRadius.zero,
      semanticLabel: '${s.name}, ${Fmt.money(s.price)} ${Fmt.cycle(s.cycle).toLowerCase()}, $trailingCaption',
      child: AnimatedOpacity(
        opacity: dimmed ? 0.55 : 1,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              MerchantAvatar(
                logo: merchant?.logo ?? const MerchantLogo.monogram(),
                name: s.name,
                // Vuela hasta la cabecera del detalle.
                heroTag: subscriptionLogoHeroTag(s.id),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(s.name,
                              style: AppType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        if (s.status == SubscriptionStatus.trial) ...[
                          const SizedBox(width: 6),
                          const NotionTag('Prueba'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${s.category.label} · ${Fmt.cycle(s.cycle)}',
                      style: AppType.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Fmt.money(s.price), style: AppType.amount),
                  const SizedBox(height: 1),
                  Text(
                    trailingCaption,
                    style: AppType.caption.copyWith(
                      color: days != null && days <= 1 && !dimmed ? AppColors.ink : null,
                      fontWeight: days != null && days <= 1 && !dimmed ? FontWeight.w600 : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
