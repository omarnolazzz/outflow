import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/di/core_providers.dart';
import '../../../../core/domain/money.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/amount_keypad.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../domain/wallet_account.dart';
import '../wallet_providers.dart';

/// Nombres que se ofrecen al crear una cuenta; el texto sigue siendo libre.
const kAccountNameSuggestions = ['BCP', 'BBVA', 'Interbank', 'Scotiabank', 'Dale', 'Yape', 'Plin', 'Efectivo'];

/// Tipo que se propone para una sugerencia (null = no cambia el elegido).
AccountType? suggestedTypeFor(String name) => switch (name) {
      'Efectivo' => AccountType.cash,
      'Dale' || 'Yape' || 'Plin' => AccountType.wallet,
      'BCP' || 'BBVA' || 'Interbank' || 'Scotiabank' => AccountType.bank,
      _ => null,
    };

String accountTypeName(AccountType t) => switch (t) {
      AccountType.bank => 'Banco',
      AccountType.wallet => 'Billetera',
      AccountType.cash => 'Efectivo',
      AccountType.creditCard => 'Tarjeta de crédito',
      AccountType.other => 'Otra',
    };

/// Abre la hoja para crear una cuenta o editar la de [editing] (nombre, tipo y
/// dígitos; el saldo se corrige con "Mi saldo real es…").
Future<void> showAccountEditor(BuildContext context, {WalletAccount? editing}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => AccountEditorSheet(editing: editing),
    ));

class AccountEditorSheet extends ConsumerStatefulWidget {
  const AccountEditorSheet({super.key, this.editing});
  final WalletAccount? editing;

  @override
  ConsumerState<AccountEditorSheet> createState() => _AccountEditorSheetState();
}

class _AccountEditorSheetState extends ConsumerState<AccountEditorSheet> {
  late final _name = TextEditingController(text: widget.editing?.name ?? '');
  late final _digits = TextEditingController(text: widget.editing?.lastDigits ?? '');
  final AmountInput _balance = AmountInput();
  late AccountType _type = widget.editing?.type ?? AccountType.bank;
  String? _currency;
  bool _saving = false;

  WalletAccount? get _e => widget.editing;

  @override
  void initState() {
    super.initState();
    _balance.addListener(() => setState(() {}));
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _digits.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _suggest(String name) {
    HapticFeedback.selectionClick();
    _name.text = name;
    final type = suggestedTypeFor(name);
    if (type != null && _e == null) _type = type;
    setState(() {});
  }

  Future<void> _save(String currency) async {
    setState(() => _saving = true);
    final digits = _digits.text.trim();
    final lastDigits = digits.isEmpty || _type == AccountType.cash ? null : digits;
    final e = _e;
    final account = e != null
        ? WalletAccount(
            id: e.id,
            name: _name.text.trim(),
            type: _type,
            currency: e.currency,
            initialMinor: e.initialMinor,
            initialDate: e.initialDate,
            lastDigits: lastDigits,
            isDefault: e.isDefault,
            archived: e.archived,
          )
        : WalletAccount(
            id: const Uuid().v4(),
            name: _name.text.trim(),
            type: _type,
            currency: currency,
            // Lo tecleado es el saldo de este instante; en una tarjeta, lo que se debe.
            initialMinor: _type == AccountType.creditCard ? -_balance.minor : _balance.minor,
            initialDate: ref.read(nowProvider),
            lastDigits: lastDigits,
          );
    await ref.read(accountActionsProvider).save(account);
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final currency = _currency ?? _e?.currency ?? ref.watch(walletSettingsProvider).value?.currency ?? 'PEN';
    final creating = _e == null;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final isCard = _type == AccountType.creditCard;

    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return SheetScaffold(
      title: creating ? 'Nueva cuenta' : 'Editar cuenta',
      closeIcon: true,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (creating && !keyboardOpen) AmountKeypad(input: _balance),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Guardar',
            loading: _saving,
            onTap: _name.text.trim().isEmpty ? null : () => _save(currency),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        children: [
          e(SurfaceCard(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: TextField(
              controller: _name,
              style: AppType.body,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [LengthLimitingTextInputFormatter(30)],
              decoration: const InputDecoration(
                hintText: 'Nombre de la cuenta',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          )),
          if (creating) ...[
            const SizedBox(height: 10),
            e(Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in kAccountNameSuggestions)
                  _Chip(label: s, selected: _name.text.trim() == s, onTap: () => _suggest(s)),
              ],
            )),
          ],
          const SizedBox(height: 18),
          e(const _Label('Tipo')),
          e(Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in AccountType.values)
                _Chip(
                  label: accountTypeName(t),
                  selected: _type == t,
                  onTap: () => setState(() => _type = t),
                ),
            ],
          )),
          if (creating) ...[
            const SizedBox(height: 18),
            e(const _Label('Moneda')),
            e(Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in kSupportedCurrencies)
                  _Chip(label: c, selected: currency == c, onTap: () => setState(() => _currency = c)),
              ],
            )),
          ],
          if (_type != AccountType.cash) ...[
            const SizedBox(height: 18),
            e(SurfaceCard(
              radius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: TextField(
                controller: _digits,
                style: AppType.body,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                decoration: const InputDecoration(
                  hintText: 'Últimos 4 dígitos (opcional)',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            )),
          ],
          if (creating) ...[
            const SizedBox(height: 22),
            e(Center(child: Text(isCard ? 'Lo que debes hoy' : 'Saldo de hoy', style: AppType.subhead))),
            const SizedBox(height: 6),
            e(Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedDefaultTextStyle(
                  duration: AppMotion.short,
                  style: AppType.amountHero.copyWith(
                    fontSize: 48,
                    color: _balance.isEmpty ? AppColors.inkTertiary : AppColors.ink,
                  ),
                  child: Text(_balance.display(currency)),
                ),
              ),
            )),
          ] else ...[
            const SizedBox(height: 18),
            Center(
              child: Text(
                'Moneda ${Fmt.symbol(_e!.currency)} ${_e!.currency}. Para corregir el saldo usa "Mi saldo real es…".',
                textAlign: TextAlign.center,
                style: AppType.footnote.copyWith(color: AppColors.inkTertiary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(text, style: AppType.subhead.copyWith(fontWeight: FontWeight.w500)),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        highlight: false,
        scale: 0.95,
        borderRadius: BorderRadius.circular(18),
        semanticLabel: label,
        child: AnimatedContainer(
          duration: AppMotion.short,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: ShapeDecoration(
            color: selected ? AppColors.accentSoft : AppColors.surface,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: selected ? AppColors.accent : AppColors.separator, width: selected ? 1.5 : 1),
            ),
          ),
          child: Text(
            label,
            style: AppType.subhead.copyWith(color: AppColors.ink, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
          ),
        ),
      );
}
