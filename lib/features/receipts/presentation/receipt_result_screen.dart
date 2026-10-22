import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/domain/billing_cycle.dart';
import '../../../core/domain/money.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/amount_keypad.dart';
import '../../../core/widgets/list_row.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../wallet/domain/category.dart';
import '../../wallet/domain/expense_hints.dart';
import '../../wallet/domain/movement.dart';
import '../../wallet/domain/payment_match.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../../wallet/presentation/widgets/category_icon.dart';
import '../domain/receipt.dart';

/// Resultado de leer un ticket: todo editable antes de guardar. Si el pago
/// ya estaba registrado (p. ej. con Apple Pay), se completa en vez de duplicarlo.
class ReceiptResultScreen extends ConsumerStatefulWidget {
  const ReceiptResultScreen({super.key, required this.receipt, this.readFailed = false});

  final ReceiptData receipt;

  /// No se pudo leer el texto: el usuario lo completa a mano.
  final bool readFailed;

  @override
  ConsumerState<ReceiptResultScreen> createState() => _ReceiptResultScreenState();
}

class _ReceiptResultScreenState extends ConsumerState<ReceiptResultScreen> {
  late final _merchant = TextEditingController(text: widget.receipt.merchant ?? '');
  late final AmountInput _total = AmountInput()..setMinor(widget.receipt.totalMinor ?? 0);
  late List<ReceiptItem> _items = List.of(widget.receipt.items);
  DateTime? _date;
  String? _categoryId;
  bool _editingTotal = false;
  bool _saving = false;

  /// Gastos registrados (para "¿Es este pago?"); se escuchan desde build.
  List<Movement> _movements = const [];

  @override
  void initState() {
    super.initState();
    _date = widget.receipt.date;
    _total.addListener(() => setState(() {}));
    _editingTotal = (widget.receipt.totalMinor ?? 0) == 0;
  }

  @override
  void dispose() {
    _merchant.dispose();
    _total.dispose();
    super.dispose();
  }

  String _currency() =>
      widget.receipt.currency ?? ref.read(walletSettingsProvider).value?.currency ?? 'PEN';

  String _itemsNote(String currency) => [
        for (final i in _items)
          '${i.quantity > 1 ? '${i.quantity}× ' : ''}${i.name} · ${Fmt.money(Money(i.amountMinor, currency))}',
      ].join('\n');

  Future<void> _pickDate(DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 1),
      lastDate: ref.read(nowProvider),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickCategory(List<Category> options, String? current) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in options)
                Pressable(
                  onTap: () => Navigator.pop(context, c.id),
                  highlight: false,
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 76,
                    child: Column(
                      children: [
                        CategoryBadge(category: c, size: 44),
                        const SizedBox(height: 4),
                        Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.caption.copyWith(
                          color: AppColors.ink,
                          fontWeight: c.id == current ? FontWeight.w700 : FontWeight.w400,
                        )),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _categoryId = picked);
  }

  /// "¿Es este pago?": el gasto elegido, null si es otro, o cancelado.
  Future<(bool, Movement?)> _askMatch(List<Movement> candidates) async {
    final picked = await showModalBottomSheet<Object>(
      context: context,
      useRootNavigator: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('¿Es este pago?', style: AppType.title2),
              const SizedBox(height: 4),
              Text('Ya registraste un gasto parecido. Si es el mismo, lo completamos con el ticket.', style: AppType.subhead),
              const SizedBox(height: 14),
              for (final m in candidates.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SurfaceCard(
                    onTap: () => Navigator.pop(context, m),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.title.isEmpty ? 'Gasto' : m.title, style: AppType.headline),
                              Text(
                                '${Fmt.dateShort(m.date)}${m.origin == MovementOrigin.applePay ? ' · Apple Pay' : ''}',
                                style: AppType.footnote,
                              ),
                            ],
                          ),
                        ),
                        Text(Fmt.money(m.amount), style: AppType.amount),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              PrimaryButton(label: 'No, es otro', secondary: true, onTap: () => Navigator.pop(context, false)),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return (false, null);
    return (true, picked is Movement ? picked : null);
  }

  Future<void> _save(String categoryId) async {
    final now = ref.read(nowProvider);
    final currency = _currency();
    final date = _date ?? now;
    final merchant = _merchant.text.trim();
    final movements = _movements;
    final candidates = findMatchingPayments(
      movements: movements,
      amountMinor: _total.minor,
      merchant: merchant,
      date: date,
    );

    Movement? existing;
    if (candidates.isNotEmpty) {
      final (decided, chosen) = await _askMatch(candidates);
      if (!decided) return;
      existing = chosen;
    }

    setState(() => _saving = true);
    final note = _itemsNote(currency);
    final movement = existing != null
        ? existing.copyWith(
            // Se completa el pago tal como se registró: su moneda no cambia.
            amount: Money(_total.minor, existing.amount.currency),
            title: merchant.isEmpty ? existing.title : merchant,
            note: [if (existing.note.isNotEmpty) existing.note, note].join('\n'),
            date: existing.date,
          )
        : Movement(
            id: const Uuid().v4(),
            kind: MovementKind.expense,
            amount: Money(_total.minor, currency),
            categoryId: categoryId,
            date: DateUtils.isSameDay(date, now) ? now : date,
            title: merchant,
            note: note,
            origin: MovementOrigin.ticket,
            createdAt: now,
          );
    await ref.read(walletActionsProvider).save(movement);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(existing != null ? 'Gasto completado con el ticket.' : 'Gasto guardado.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowProvider);
    final currency = _currency();
    _movements = ref.watch(movementsProvider).value ?? const [];
    final all = ref.watch(categoriesProvider).value ?? const <Category>[];
    final options = all.where((c) => c.kind == MovementKind.expense && !c.reserved).toList();
    _categoryId ??= options.isEmpty
        ? null
        : suggestCategory(
              merchant: _merchant.text,
              history: ref.read(movementsProvider).value ?? const [],
              categories: options,
            ) ??
            options.first.id;
    final category = options.where((c) => c.id == _categoryId).firstOrNull;
    final date = _date ?? now;

    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return SheetScaffold(
      title: 'Ticket',
      closeIcon: true,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.ease,
            alignment: Alignment.bottomCenter,
            child: _editingTotal ? AmountKeypad(input: _total) : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Guardar gasto',
            loading: _saving,
            onTap: _total.minor > 0 && _categoryId != null ? () => _save(_categoryId!) : null,
          ),
          const SizedBox(height: 8),
          Opacity(
            opacity: 0.5,
            child: PrimaryButton(
              label: 'Dividir con amigos',
              secondary: true,
              icon: const Icon(LucideIcons.users, size: 18, color: AppColors.ink),
              onTap: null,
            ),
          ),
          const SizedBox(height: 4),
          Text('Disponible con Amigos', style: AppType.caption),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          if (widget.receipt.fromAi || widget.readFailed)
            e(Center(
              child: widget.readFailed
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: ShapeDecoration(
                        color: AppColors.dangerSoft,
                        shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.scanText, size: 18, color: AppColors.danger),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No pudimos leer el ticket. Complétalo a mano o prueba con otra foto más nítida.',
                              style: AppType.footnote.copyWith(color: AppColors.ink),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const StatusPill('Leído con IA', tone: PillTone.accent, icon: LucideIcons.sparkles),
            )),
          const SizedBox(height: 10),
          e(TextField(
            controller: _merchant,
            textAlign: TextAlign.center,
            style: AppType.title1,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Comercio',
              filled: false,
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          )),
          const SizedBox(height: 6),
          e(Center(
            child: Pressable(
              onTap: () => setState(() => _editingTotal = !_editingTotal),
              highlight: false,
              borderRadius: BorderRadius.circular(16),
              semanticLabel: 'Total',
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _total.display(currency),
                  style: AppType.amountHero.copyWith(color: _total.isEmpty ? AppColors.inkTertiary : AppColors.ink),
                ),
              ),
            ),
          )),
          const SizedBox(height: 18),
          e(ListRow(
            label: 'Fecha',
            value: DateUtils.isSameDay(date, now) ? 'Hoy' : Fmt.dateShort(dateOnly(date)),
            onTap: () => _pickDate(date),
          )),
          const SizedBox(height: 8),
          e(ListRow(
            label: 'Categoría',
            value: category?.name ?? '—',
            leading: category == null ? null : CategoryBadge(category: category, size: 28),
            onTap: options.isEmpty ? null : () => _pickCategory(options, _categoryId),
          )),
          if (_items.isNotEmpty) ...[
            e(const SectionHeader('Productos')),
            e(SurfaceCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final (i, item) in _items.indexed)
                    Dismissible(
                      key: ValueKey('$i-${item.name}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 18),
                        color: AppColors.dangerSoft,
                        child: const Icon(LucideIcons.trash2, color: AppColors.danger),
                      ),
                      onDismissed: (_) => setState(() => _items = List.of(_items)..removeAt(i)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            if (item.quantity > 1) ...[
                              StatusPill('${item.quantity}×'),
                              const SizedBox(width: 8),
                            ],
                            Expanded(child: Text(item.name, style: AppType.body)),
                            Text(Fmt.money(Money(item.amountMinor, currency)), style: AppType.amount),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }
}
