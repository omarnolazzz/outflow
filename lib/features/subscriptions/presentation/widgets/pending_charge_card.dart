import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/presentation/widgets/merchant_avatar.dart';
import '../../domain/charge_schedule.dart';
import '../../domain/dashboard_summary.dart';
import 'confirm_charge_sheet.dart';

/// "¿Próximo cobro el 18 nov?" con respuesta en un toque ("Sí") o detallada.
class PendingChargeCard extends ConsumerWidget {
  const PendingChargeCard({super.key, required this.item, required this.merchant});

  final PendingCharge item;
  final Merchant? merchant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = item.subscription;
    final first = suggestNext(s, item.charge).first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MerchantAvatar(logo: merchant?.logo ?? const MerchantLogo.monogram(), name: s.name, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: AppType.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('Se cobró el ${Fmt.dateShort(item.charge)}', style: AppType.footnote),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('¿Próximo cobro el ${Fmt.dateShort(first.date)}?', style: AppType.title2.copyWith(fontSize: 19)),
            const SizedBox(height: 2),
            Text(first.label, style: AppType.footnote),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PillButton(
                  label: 'Sí',
                  icon: LucideIcons.check,
                  filled: true,
                  onTap: () => confirmFirstSuggestion(context, ref, s, item.charge),
                ),
                PillButton(
                  label: 'Otra fecha',
                  onTap: () => showConfirmChargeSheet(context, ref, s, item.charge),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
