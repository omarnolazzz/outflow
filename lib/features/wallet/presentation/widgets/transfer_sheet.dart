import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/core_providers.dart';
import '../../../../core/domain/billing_cycle.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/amount_keypad.dart';
import '../../../../core/widgets/list_row.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../domain/account_balances.dart';
import '../../domain/wallet_account.dart';
import '../wallet_providers.dart';
import 'account_editor_sheet.dart';
import 'account_picker.dart';

/// Abre la hoja de transferencia entre dos cuentas propias. Con menos de dos
/// cuentas sin archivar pide crear otra.
Future<void> showTransferSheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  final List<WalletAccount> accounts;
  try {
    accounts = await container.read(accountRepositoryProvider).watchAll().first;
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  if (accounts.where((a) => !a.archived).length < 2) {
    final create = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('Necesitas otra cuenta'),
        content: const Text('Una transferencia mueve dinero entre dos de tus cuentas. Crea la segunda para empezar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ahora no')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Crear cuenta')),
        ],
      ),
    );
    if (create == true && context.mounted) await showAccountEditor(context);
    return;
  }
  await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => const TransferSheet(),
  ));
}

class TransferSheet extends ConsumerStatefulWidget {
  const TransferSheet({super.key, this.fromId});

  /// Cuenta de origen con la que empieza (por defecto, la cuenta por defecto).
  final String? fromId;

  @override
  ConsumerState<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<TransferSheet> {
  final AmountInput _sent = AmountInput();
  final AmountInput _received = AmountInput();
  final _note = TextEditingController();
  late String? _fromId = widget.fromId;
  String? _toId;
  DateTime? _date;

  /// Entre monedas distintas hay dos importes: cuál se teclea ahora.
  bool _editingReceived = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _sent.addListener(() => setState(() {}));
    _received.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _sent.dispose();
    _received.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate(DateTime current, DateTime now) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save(WalletAccount from, WalletAccount to, bool cross) async {
    setState(() => _saving = true);
    final now = ref.read(nowProvider);
    final date = _date ?? now;
    final transfer = makeTransfer(
      from: from,
      to: to,
      amountMinor: _sent.minor,
      receivedMinor: cross ? _received.minor : null,
      // Hoy conserva la hora: ordena bien los movimientos de un mismo día.
      date: DateUtils.isSameDay(date, now) ? now : date,
      note: _note.text.trim(),
      now: now,
    );
    await ref.read(walletActionsProvider).save(transfer);
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeAccountsProvider);
    final now = ref.watch(nowProvider);
    final from = resolveAccount(active, _fromId);
    final others = selectableAccounts(active, excludeId: from?.id);
    final to = others.where((a) => a.id == _toId).firstOrNull ?? others.firstOrNull;
    final date = _date ?? now;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    if (from == null || to == null) {
      return SheetScaffold(title: 'Transferencia', closeIcon: true, child: const SizedBox.shrink());
    }
    final cross = from.currency != to.currency;
    final editingReceived = cross && _editingReceived;
    final ready = _sent.minor > 0 && (!cross || _received.minor > 0);

    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return SheetScaffold(
      title: 'Transferencia',
      closeIcon: true,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!keyboardOpen) AmountKeypad(input: editingReceived ? _received : _sent),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Guardar',
            loading: _saving,
            onTap: ready ? () => _save(from, to, cross) : null,
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        children: [
          e(cross
              ? Row(
                  children: [
                    Expanded(
                      child: _AmountBox(
                        label: 'Envías',
                        text: _sent.display(from.currency),
                        empty: _sent.isEmpty,
                        selected: !editingReceived,
                        onTap: () => setState(() => _editingReceived = false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AmountBox(
                        label: 'Recibe',
                        text: _received.display(to.currency),
                        empty: _received.isEmpty,
                        selected: editingReceived,
                        onTap: () => setState(() => _editingReceived = true),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AnimatedDefaultTextStyle(
                      duration: AppMotion.short,
                      style: AppType.amountHero.copyWith(
                        fontSize: 52,
                        color: _sent.isEmpty ? AppColors.inkTertiary : AppColors.ink,
                      ),
                      child: Text(_sent.display(from.currency)),
                    ),
                  ),
                )),
          const SizedBox(height: 18),
          e(AccountPicker(
            key: const ValueKey('transfer-from'),
            label: 'Desde',
            alwaysShow: true,
            selectedId: from.id,
            onChanged: (a) => setState(() {
              _fromId = a.id;
              _editingReceived = false;
            }),
          )),
          const SizedBox(height: 12),
          e(AccountPicker(
            key: const ValueKey('transfer-to'),
            label: 'A',
            alwaysShow: true,
            excludeId: from.id,
            selectedId: to.id,
            onChanged: (a) => setState(() {
              _toId = a.id;
              _editingReceived = false;
            }),
          )),
          const SizedBox(height: 12),
          e(ListRow(
            label: 'Fecha',
            value: DateUtils.isSameDay(date, now) ? 'Hoy' : Fmt.dateLong(dateOnly(date)),
            onTap: () => _pickDate(date, now),
          )),
          const SizedBox(height: 8),
          e(SurfaceCard(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: TextField(
              controller: _note,
              style: AppType.body,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Añadir una nota',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          )),
        ],
      ),
    );
  }
}

/// Uno de los dos importes de una transferencia entre monedas.
class _AmountBox extends StatelessWidget {
  const _AmountBox({required this.label, required this.text, required this.empty, required this.selected, required this.onTap});
  final String label;
  final String text;
  final bool empty;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        highlight: false,
        scale: 0.97,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: AppMotion.short,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: ShapeDecoration(
            color: selected ? AppColors.accentSoft : AppColors.surface,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: selected ? AppColors.accent : Colors.transparent, width: 1.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppType.caption),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  text,
                  style: AppType.amountLarge.copyWith(color: empty ? AppColors.inkTertiary : AppColors.ink),
                ),
              ),
            ],
          ),
        ),
      );
}
