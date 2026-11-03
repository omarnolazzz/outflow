import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/domain/money.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/amount_text.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../domain/wallet_account.dart';
import '../../domain/movement.dart';
import '../wallet_providers.dart';
import '../widgets/account_editor_sheet.dart';
import '../widgets/account_picker.dart';
import '../widgets/adjust_balance_sheet.dart';
import '../widgets/movement_row.dart';
import '../widgets/movement_sheet.dart';
import '../widgets/transfer_sheet.dart';

/// Abre Cuentas sobre la barra de pestañas.
Future<void> openAccounts(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const AccountsScreen()));

/// Lista de cuentas con su saldo y el total por moneda.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsState = ref.watch(accountsProvider);
    final all = accountsState.hasValue ? accountsState.value! : const <WalletAccount>[];
    final balancesState = ref.watch(accountBalancesProvider);
    final balances = balancesState.hasValue ? balancesState.value! : const <String, int>{};
    final totals = ref.watch(accountTotalsProvider);
    final main = ref.watch(walletSettingsProvider).value?.currency ?? 'PEN';
    final active = all.where((a) => !a.archived).toList();
    final archived = all.where((a) => a.archived).toList();
    final others = [
      for (final e in (totals ?? const <String, int>{}).entries)
        if (e.key != main && e.value != 0) Money(e.value, e.key),
    ];

    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return SheetScaffold(
      title: 'Cuentas',
      trailing: CircleIconButton(
        icon: LucideIcons.plus,
        label: 'Nueva cuenta',
        onTap: () => showAccountEditor(context),
      ),
      bottom: PrimaryButton(
        label: 'Transferencia',
        secondary: true,
        icon: const Icon(LucideIcons.arrowLeftRight, size: 18, color: AppColors.ink),
        onTap: () => showTransferSheet(context),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          e(SurfaceCard(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Saldo en cuentas', style: AppType.subhead.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AmountText(Money(totals?[main] ?? 0, main), style: AppType.amountHero),
                ),
                if (others.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('+ ${others.map(Fmt.money).join(' · ')} en otras monedas', style: AppType.footnote),
                ],
              ],
            ),
          )),
          const SizedBox(height: 12),
          for (final a in active)
            e(Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AccountRow(account: a, balance: balances[a.id] ?? 0),
            )),
          if (archived.isNotEmpty) ...[
            e(const SectionHeader('Archivadas')),
            for (final a in archived)
              e(Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AccountRow(account: a, balance: balances[a.id] ?? 0, dimmed: true),
              )),
          ],
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.balance, this.dimmed = false});
  final WalletAccount account;
  final int balance;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      accountTypeName(account.type),
      if (account.isDefault) 'Por defecto',
      if (account.lastDigits != null) '•••• ${account.lastDigits}',
    ].join(' · ');
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => AccountDetailScreen(accountId: account.id)),
      ),
      child: Opacity(
        opacity: dimmed ? 0.6 : 1,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
              child: Icon(accountTypeIcon(account.type), size: 19, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.name, style: AppType.headline.copyWith(fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(subtitle, style: AppType.footnote, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(Fmt.money(Money(balance, account.currency)), style: AppType.amount),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una cuenta: saldo, ajuste, transferencia, sus movimientos y su gestión.
class AccountDetailScreen extends ConsumerWidget {
  const AccountDetailScreen({super.key, required this.accountId});
  final String accountId;

  Future<void> _confirmArchive(BuildContext context, WidgetRef ref, WalletAccount account, bool used) async {
    final verb = used ? 'Archivar' : 'Borrar';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿$verb esta cuenta?'),
        content: Text(used
            ? 'Sus movimientos se conservan, pero deja de aparecer en los totales y al elegir cuenta.'
            : 'No tiene movimientos, así que se borra del todo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(verb, style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(accountActionsProvider).delete(account.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsState = ref.watch(accountsProvider);
    final all = accountsState.hasValue ? accountsState.value! : const <WalletAccount>[];
    final account = all.where((a) => a.id == accountId).firstOrNull;
    if (account == null) return const SheetScaffold(title: 'Cuenta', child: SizedBox.shrink());

    final balancesState = ref.watch(accountBalancesProvider);
    final balance = balancesState.hasValue ? balancesState.value![account.id] ?? 0 : 0;
    final movementsState = ref.watch(movementsProvider);
    final movements = movementsState.hasValue ? movementsState.value! : const <Movement>[];
    final defaultId = defaultAccountOf(all)?.id;
    final mine = [
      for (final m in movements)
        if ((m.accountId ?? defaultId) == account.id || m.toAccountId == account.id) m,
    ]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
      });
    final categories = ref.watch(categoryIndexProvider);
    final used = mine.isNotEmpty;

    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return SheetScaffold(
      title: account.name,
      trailing: CircleIconButton(
        icon: LucideIcons.pencil,
        label: 'Editar cuenta',
        onTap: () => showAccountEditor(context, editing: account),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          e(SurfaceCard(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusPill(accountTypeName(account.type)),
                    if (account.lastDigits != null) StatusPill('•••• ${account.lastDigits}'),
                    if (account.isDefault) const StatusPill('Por defecto', tone: PillTone.accent),
                    if (account.archived) const StatusPill('Archivada', tone: PillTone.danger),
                  ],
                ),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AmountText(Money(balance, account.currency), style: AppType.amountHero),
                ),
              ],
            ),
          )),
          if (!account.archived) ...[
            const SizedBox(height: 12),
            e(PrimaryButton(label: 'Mi saldo real es…', onTap: () => showAdjustBalance(context, account))),
            const SizedBox(height: 8),
            e(PrimaryButton(
              label: 'Transferencia',
              secondary: true,
              icon: const Icon(LucideIcons.arrowLeftRight, size: 18, color: AppColors.ink),
              onTap: () => showTransferSheet(context),
            )),
          ],
          e(const SectionHeader('Movimientos')),
          e(mine.isEmpty
              ? SurfaceCard(child: Text('Esta cuenta aún no tiene movimientos.', style: AppType.subhead))
              : SurfaceCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      for (final m in mine.take(30))
                        MovementRow(
                          movement: m,
                          category: categories[m.categoryId],
                          showDate: true,
                          onTap: m.isTransferOrAdjustment ? null : () => showMovementSheet(context, editing: m),
                        ),
                    ],
                  ),
                )),
          const SizedBox(height: 20),
          if (account.archived)
            e(PrimaryButton(
              label: 'Restaurar cuenta',
              secondary: true,
              onTap: () async {
                await ref.read(accountActionsProvider).save(account.copyWith(archived: false));
              },
            ))
          else if (!account.isDefault) ...[
            e(PrimaryButton(
              label: 'Usar como cuenta por defecto',
              secondary: true,
              onTap: () => ref.read(accountActionsProvider).setDefault(account.id),
            )),
            const SizedBox(height: 4),
            e(Center(
              child: Pressable(
                onTap: () => _confirmArchive(context, ref, account, used),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    used ? 'Archivar cuenta' : 'Borrar cuenta',
                    style: AppType.callout.copyWith(color: AppColors.danger),
                  ),
                ),
              ),
            )),
          ],
        ],
      ),
    );
  }
}
