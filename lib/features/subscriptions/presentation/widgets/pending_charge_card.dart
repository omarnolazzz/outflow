import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/notion_widgets.dart';
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
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: NotionBlock(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MerchantAvatar(logo: merchant?.logo ?? const MerchantLogo.monogram(), name: s.name, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: AppType.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('Se cobró el ${Fmt.dateShort(item.charge)}', style: AppType.caption),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('¿Próximo cobro el ${Fmt.dateShort(first.date)}?', style: AppType.headline),
            Text(first.label, style: AppType.caption),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlineAction(
                  label: 'Sí',
                  icon: LucideIcons.check,
                  filled: true,
                  onTap: () => confirmFirstSuggestion(context, ref, s, item.charge),
                ),
                OutlineAction(
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
