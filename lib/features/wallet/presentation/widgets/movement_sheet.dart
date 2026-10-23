import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/di/core_providers.dart';
import '../../../../core/domain/billing_cycle.dart';
import '../../../../core/domain/money.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/amount_keypad.dart';
import '../../../../core/widgets/list_row.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/segmented_control.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../../friends/presentation/friends_providers.dart';
import '../../../friends/presentation/split_editor_screen.dart';
import '../../../receipts/presentation/scan_receipt_flow.dart';
import '../../domain/apple_pay_link.dart';
import '../../domain/category.dart';
import '../../domain/expense_hints.dart';
import '../../domain/movement.dart';
import '../wallet_providers.dart';
import 'category_icon.dart';

/// Abre la hoja para registrar (o editar) un gasto o ingreso.
Future<void> showMovementSheet(
  BuildContext context, {
  MovementKind kind = MovementKind.expense,
  Movement? editing,
  MovementDraft? draft,
}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => MovementSheet(kind: editing?.kind ?? kind, editing: editing, draft: draft),
    ));

class MovementSheet extends ConsumerStatefulWidget {
  const MovementSheet({super.key, required this.kind, this.editing, this.draft});
  final MovementKind kind;
  final Movement? editing;

  /// Gasto llegado de fuera (atajo de Apple Pay, ticket) para confirmar.
  final MovementDraft? draft;

  @override
  ConsumerState<MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends ConsumerState<MovementSheet> {
  late MovementKind _kind = widget.kind;
  late final AmountInput _amount = AmountInput()..setMinor(widget.editing?.amount.minor ?? widget.draft?.amountMinor ?? 0);
  late final _title = TextEditingController(text: widget.editing?.title ?? widget.draft?.title ?? '');
  late final _note = TextEditingController(text: widget.editing?.note ?? widget.draft?.note ?? '');
  String? _categoryId;
  DateTime? _date;
  bool _saving = false;

  /// "Dividir con amigos": al guardar abre el editor de reparto en vez de guardar el gasto.
  bool _split = false;

  /// La categoría del comercio del borrador ya se propuso (una vez, al cargar).
  bool _suggested = false;

  Movement? get _e => widget.editing;

  /// Un cobro de suscripción solo admite cambiar importe, fecha y nota.
  bool get _isCharge => _e?.origin == MovementOrigin.subscription;

  /// Tu parte de un gasto compartido solo admite cambiar categoría y nota.
  bool get _isSplit => _e?.origin == MovementOrigin.split;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
    _categoryId = _e?.categoryId ?? widget.draft?.categoryId;
    _date = _e?.date ?? widget.draft?.date;
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Última categoría usada de ese tipo, o la primera de la lista.
  String? _defaultCategory(List<Category> options) {
    final movements = ref.read(movementsProvider).value ?? const [];
    final ids = {for (final c in options) c.id};
    final recent = movements.where((m) => m.kind == _kind && m.origin == MovementOrigin.manual && ids.contains(m.categoryId)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return recent.firstOrNull?.categoryId ?? options.firstOrNull?.id;
  }

  /// Solo para gastos que llegan de fuera: el mismo pago apuntado hace poco.
  Movement? _duplicate(DateTime now) {
    final d = widget.draft;
    if (d == null || _e != null || _amount.minor <= 0) return null;
    return findRecentDuplicate(
      movements: ref.watch(movementsProvider).value ?? const [],
      amountMinor: _amount.minor,
      merchant: _title.text,
      now: now,
    );
  }

  Future<void> _pickDate(DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 5),
      lastDate: DateTime(current.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  /// El interruptor solo existe en un gasto nuevo y con Amigos disponible.
  bool get _canSplit =>
      _e == null && _kind == MovementKind.expense && ref.read(socialRepositoryProvider).available;

  Future<void> _save(String currency, String categoryId, DateTime date) async {
    final now = ref.read(nowProvider);
    if (_split && _canSplit) {
      // En vez de guardar el gasto, se reparte: el editor lo guardará compartido.
      final draft = SplitDraft(
        totalMinor: _amount.minor,
        currency: widget.draft?.currency ?? currency,
        title: _title.text.trim(),
        date: DateUtils.isSameDay(date, now) ? now : date,
        categoryId: categoryId,
      );
      // El editor se abre encima: si se cierra sin guardar, la hoja sigue
      // aquí con el pago intacto; solo se cierra cuando el reparto se guarda.
      final saved = await showSplitEditor(context, draft: draft);
      if (saved && mounted) Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    // Conserva la hora si se registra hoy (ordena bien los de un mismo día).
    final when = DateUtils.isSameDay(date, now) && _e == null ? now : date;
    final money = Money(_amount.minor, _e?.amount.currency ?? widget.draft?.currency ?? currency);
    final movement = _e == null
        ? Movement(
            id: const Uuid().v4(),
            kind: _kind,
            amount: money,
            categoryId: categoryId,
            date: when,
            title: _title.text.trim(),
            note: _note.text.trim(),
            origin: widget.draft?.origin ?? MovementOrigin.manual,
            createdAt: now,
          )
        : _e!.copyWith(
            kind: _isCharge || _isSplit ? null : _kind,
            amount: money,
            categoryId: _isCharge ? null : categoryId,
            date: when,
            title: _isCharge || _isSplit ? null : _title.text.trim(),
            note: _note.text.trim(),
            // Solo un importe cambiado a mano protege el cobro de los cambios de precio.
            userEdited: _isCharge && money != _e!.amount ? true : null,
          );
    await ref.read(walletActionsProvider).save(movement);
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final actions = ref.read(walletActionsProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final deleted = await actions.delete(_e!.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (deleted == null) return;
    HapticFeedback.heavyImpact();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Movimiento borrado.'),
        action: SnackBarAction(label: 'Deshacer', onPressed: () => actions.restore(deleted)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(walletSettingsProvider).value?.currency ?? 'PEN';
    final now = ref.watch(nowProvider);
    final all = ref.watch(categoriesProvider).value ?? const <Category>[];
    // Un gasto que llega de fuera propone la categoría de ese comercio.
    if (!_suggested && all.isNotEmpty && widget.draft != null) {
      _suggested = true;
      _categoryId ??= suggestCategory(
        merchant: widget.draft!.title,
        history: ref.read(movementsProvider).value ?? const [],
        categories: all,
      );
    }
    final options = all.where((c) => c.kind == _kind && (!c.reserved || c.id == _categoryId)).toList();
    final categoryId = options.any((c) => c.id == _categoryId) ? _categoryId : _defaultCategory(options);
    final date = _date ?? now;
    final isExpense = _kind == MovementKind.expense;

    return SheetScaffold(
      title: _e == null ? (isExpense ? 'Nuevo gasto' : 'Nuevo ingreso') : 'Editar',
      closeIcon: true,
      trailing: _isSplit
          ? null
          : _e != null
          ? CircleIconButton(icon: LucideIcons.trash2, label: 'Borrar', onTap: _delete)
          : widget.draft == null && isExpense
              ? CircleIconButton(
                  icon: LucideIcons.scanLine,
                  label: 'Escanear ticket',
                  onTap: () {
                    // Cambia a escanear: cierra la hoja vacía y abre la cámara/galería.
                    final root = Navigator.of(context, rootNavigator: true).context;
                    Navigator.of(context).pop();
                    showScanReceipt(root);
                  },
                )
              : null,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isSplit) AmountKeypad(input: _amount),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Guardar',
            loading: _saving,
            onTap: _amount.minor > 0 && categoryId != null ? () => _save(currency, categoryId, date) : null,
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        children: [
          if (!_isCharge && !_isSplit)
            Entrance(
              child: SegmentedControl<MovementKind>(
                values: MovementKind.values,
                selected: _kind,
                label: (k) => k == MovementKind.expense ? 'Gasto' : 'Ingreso',
                onChanged: (k) => setState(() {
                  _kind = k;
                  _categoryId = null;
                }),
              ),
            ),
          const SizedBox(height: 18),
          Entrance(
            index: 1,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedDefaultTextStyle(
                  duration: AppMotion.short,
                  style: AppType.amountHero.copyWith(
                    fontSize: 52,
                    color: _amount.isEmpty ? AppColors.inkTertiary : (isExpense ? AppColors.ink : AppColors.income),
                  ),
                  child: Text('${isExpense ? '' : '+'}${_amount.display(_e?.amount.currency ?? widget.draft?.currency ?? currency)}'),
                ),
              ),
            ),
          ),
          if (_duplicate(now) case final dup?) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: ShapeDecoration(
                color: AppColors.dangerSoft,
                shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.copy, size: 16, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Posible duplicado: ya registraste ${Fmt.money(dup.amount)} en ${dup.title} '
                      'hace ${now.difference(dup.createdAt).inMinutes.clamp(1, 99)} min.',
                      style: AppType.footnote.copyWith(color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (_isSplit) ...[
            Center(
              child: Text(
                'Gasto compartido · se edita en Amigos',
                style: AppType.footnote.copyWith(color: AppColors.inkTertiary),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!_isCharge)
            Entrance(
              index: 2,
              child: SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: options.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => _CategoryChip(
                    category: options[i],
                    selected: options[i].id == categoryId,
                    onTap: () => setState(() => _categoryId = options[i].id),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          Entrance(
            index: 3,
            child: ListRow(
              label: 'Fecha',
              value: DateUtils.isSameDay(date, now) ? 'Hoy' : _capitalize(Fmt.dateLong(dateOnly(date))),
              onTap: _isSplit ? null : () => _pickDate(date),
            ),
          ),
          const SizedBox(height: 8),
          Entrance(
            index: 4,
            child: SurfaceCard(
              radius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Column(
                children: [
                  if (!_isCharge && !_isSplit) ...[
                    _Field(controller: _title, hint: isExpense ? 'Comercio o concepto' : 'Concepto'),
                    const Divider(height: 1),
                  ],
                  _Field(controller: _note, hint: 'Añadir una nota'),
                ],
              ),
            ),
          ),
          if (_e == null && isExpense && ref.watch(socialRepositoryProvider).available) ...[
            const SizedBox(height: 8),
            Entrance(
              index: 5,
              child: SurfaceCard(
                radius: 18,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Row(
                  children: [
                    const Icon(LucideIcons.users, size: 20, color: AppColors.inkSecondary),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Dividir con amigos', style: AppType.body)),
                    Switch(
                      value: _split,
                      activeTrackColor: AppColors.accent,
                      onChanged: (v) => setState(() => _split = v),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.hint});
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        style: AppType.body,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: hint,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      );
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.selected, required this.onTap});
  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        haptic: true,
        highlight: false,
        scale: 0.94,
        borderRadius: BorderRadius.circular(16),
        semanticLabel: category.name,
        child: AnimatedContainer(
          duration: AppMotion.short,
          width: 78,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: ShapeDecoration(
            color: selected ? AppColors.accentSoft : AppColors.surface,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: selected ? AppColors.accent : Colors.transparent, width: 1.5),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SelectionPop(active: selected, amount: 0.15, child: CategoryBadge(category: category, size: 36)),
              const SizedBox(height: 6),
              Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.caption.copyWith(color: AppColors.ink, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
              ),
            ],
          ),
        ),
      );
}
