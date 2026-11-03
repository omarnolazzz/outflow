import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/core_providers.dart';
import '../../../../core/domain/money.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/amount_keypad.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../domain/account_balances.dart';
import '../../domain/wallet_account.dart';
import '../wallet_providers.dart';

/// "Mi saldo real es…": el usuario dice cuánto tiene de verdad en [account] y
/// se registra un ajuste de saldo por la diferencia.
Future<void> showAdjustBalance(BuildContext context, WalletAccount account) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => AdjustBalanceSheet(accountId: account.id),
    ));

class AdjustBalanceSheet extends ConsumerStatefulWidget {
  const AdjustBalanceSheet({super.key, required this.accountId});
  final String accountId;

  @override
  ConsumerState<AdjustBalanceSheet> createState() => _AdjustBalanceSheetState();
}

class _AdjustBalanceSheetState extends ConsumerState<AdjustBalanceSheet> {
  final AmountInput _real = AmountInput();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _real.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _real.dispose();
    super.dispose();
  }

  Future<void> _save(WalletAccount account, int currentMinor) async {
    setState(() => _saving = true);
    // En una tarjeta de crédito el usuario dice lo que debe.
    final real = account.type == AccountType.creditCard ? -_real.minor : _real.minor;
    final adjustment = makeAdjustment(
      account: account,
      currentMinor: currentMinor,
      realMinor: real,
      now: ref.read(nowProvider),
    );
    if (adjustment != null) await ref.read(walletActionsProvider).save(adjustment);
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final account = (accounts.hasValue ? accounts.value : null)?.where((a) => a.id == widget.accountId).firstOrNull;
    final balances = ref.watch(accountBalancesProvider);
    final current = balances.hasValue ? balances.value![widget.accountId] : null;
    final isCard = account?.type == AccountType.creditCard;

    return SheetScaffold(
      title: 'Ajuste de saldo',
      closeIcon: true,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AmountKeypad(input: _real),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Guardar',
            loading: _saving,
            onTap: account == null || current == null || _real.isEmpty ? null : () => _save(account, current),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        children: [
          Entrance(
            child: Center(
              child: Text(
                isCard ? 'Lo que debo en la tarjeta es…' : 'Mi saldo real es…',
                style: AppType.title2,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Entrance(
            index: 1,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedDefaultTextStyle(
                  duration: AppMotion.short,
                  style: AppType.amountHero.copyWith(
                    fontSize: 52,
                    color: _real.isEmpty ? AppColors.inkTertiary : AppColors.ink,
                  ),
                  child: Text(_real.display(account?.currency ?? 'PEN')),
                ),
              ),
            ),
          ),
          if (account != null && current != null) ...[
            const SizedBox(height: 14),
            Entrance(
              index: 2,
              child: Text(
                'Outflow calcula ${Fmt.money(Money(current, account.currency))}. '
                'Se registra la diferencia como un ajuste, sin tocar tus gastos ni "Te queda".',
                textAlign: TextAlign.center,
                style: AppType.footnote,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
