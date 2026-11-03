import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/domain/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/amount_text.dart';
import '../../../../core/widgets/surface_card.dart';
import '../screens/accounts_screen.dart';
import '../wallet_providers.dart';

/// "Saldo en cuentas": lo que hay en todas tus cuentas, en la moneda principal;
/// el resto de monedas va aparte, sin convertir. Toca → Cuentas.
class AccountsCard extends ConsumerWidget {
  const AccountsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(accountTotalsProvider);
    if (totals == null) return const SizedBox.shrink();
    final main = ref.watch(walletSettingsProvider).value?.currency ?? 'PEN';
    final count = ref.watch(activeAccountsProvider).length;
    final others = [
      for (final e in totals.entries)
        if (e.key != main && e.value != 0) Money(e.value, e.key),
    ];

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
      onTap: () => openAccounts(context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saldo en cuentas', style: AppType.subhead.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AmountText(Money(totals[main] ?? 0, main), style: AppType.amountLarge),
                ),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '+ ${others.map(Fmt.money).join(' · ')} en otras monedas',
                    style: AppType.footnote,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 2),
                Text(count == 1 ? '1 cuenta' : '$count cuentas', style: AppType.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(LucideIcons.chevronRight, size: 20, color: AppColors.inkTertiary),
        ],
      ),
    );
  }
}
