import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/domain/money.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/pressable.dart';
import '../../domain/wallet_account.dart';
import '../wallet_providers.dart';

/// Icono de cada tipo de cuenta.
IconData accountTypeIcon(AccountType type) => switch (type) {
      AccountType.bank => LucideIcons.landmark,
      AccountType.wallet => LucideIcons.smartphone,
      AccountType.cash => LucideIcons.banknote,
      AccountType.creditCard => LucideIcons.creditCard,
      AccountType.other => LucideIcons.wallet,
    };

/// La cuenta con ese [id] si se puede elegir; si no, la por defecto.
WalletAccount? resolveAccount(List<WalletAccount> active, String? id) =>
    active.where((a) => a.id == id).firstOrNull ?? defaultAccountOf(active);

/// Cuentas entre las que elegir: sin archivadas y, si se indica, en [currency].
List<WalletAccount> selectableAccounts(List<WalletAccount> active, {String? currency, String? excludeId}) => [
      for (final a in active)
        if (a.id != excludeId && (currency == null || a.currency == currency)) a,
    ];

/// Fila de cuentas para elegir una. Empieza en [selectedId] (o la por defecto).
/// Solo aparece si hay más de una cuenta sin archivar; con [currency] solo
/// ofrece las de esa moneda, y [excludeId] deja fuera una (el origen de una
/// transferencia). [alwaysShow] la muestra también con una sola.
class AccountPicker extends ConsumerWidget {
  const AccountPicker({
    super.key,
    required this.selectedId,
    required this.onChanged,
    this.label = 'Cuenta',
    this.currency,
    this.excludeId,
    this.alwaysShow = false,
  });

  final String? selectedId;
  final ValueChanged<WalletAccount> onChanged;
  final String label;
  final String? currency;
  final String? excludeId;
  final bool alwaysShow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeAccountsProvider);
    final options = selectableAccounts(active, currency: currency, excludeId: excludeId);
    if (options.isEmpty || (!alwaysShow && active.length < 2)) return const SizedBox.shrink();
    final selected = selectedId ?? resolveAccount(options, null)?.id;
    final balancesState = ref.watch(accountBalancesProvider);
    final balances = balancesState.hasValue ? balancesState.value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(label, style: AppType.subhead.copyWith(fontWeight: FontWeight.w500)),
        ),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: options.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final a = options[i];
              return _AccountChip(
                account: a,
                balance: balances == null ? null : Money(balances[a.id] ?? 0, a.currency),
                selected: a.id == selected,
                onTap: () => onChanged(a),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.account, required this.balance, required this.selected, required this.onTap});
  final WalletAccount account;
  final Money? balance;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        haptic: true,
        highlight: false,
        scale: 0.96,
        borderRadius: BorderRadius.circular(16),
        semanticLabel: account.name,
        child: AnimatedContainer(
          duration: AppMotion.short,
          constraints: const BoxConstraints(minWidth: 96, maxWidth: 170),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: ShapeDecoration(
            color: selected ? AppColors.accentSoft : AppColors.surface,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: selected ? AppColors.accent : Colors.transparent, width: 1.5),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(accountTypeIcon(account.type), size: 14, color: selected ? AppColors.accent : AppColors.inkSecondary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.subhead.copyWith(color: AppColors.ink, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
                    ),
                  ),
                ],
              ),
              if (balance != null)
                Text(Fmt.money(balance!), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.caption),
            ],
          ),
        ),
      );
}
