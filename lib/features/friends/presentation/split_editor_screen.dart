import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../../core/widgets/segmented_control.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../account/presentation/session_controller.dart';
import '../../receipts/domain/receipt.dart';
import '../../wallet/domain/category.dart';
import '../../wallet/domain/movement.dart';
import '../../wallet/domain/payment_match.dart';
import '../../wallet/presentation/widgets/account_picker.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../../wallet/presentation/widgets/category_icon.dart';
import '../../wallet/presentation/widgets/match_payment_sheet.dart';
import '../domain/shared_expense.dart';
import '../domain/split_math.dart';
import 'friends_format.dart';
import '../domain/split_movements.dart';
import 'friends_providers.dart';

/// Gasto a repartir que llega de fuera del editor (hoja de gasto, ticket).
@immutable
class SplitDraft {
  const SplitDraft({
    required this.totalMinor,
    required this.currency,
    required this.title,
    required this.date,
    required this.categoryId,
    this.items = const [],
    this.accountId,
  });

  final int totalMinor;
  final String currency;
  final String title;
  final DateTime date;
  final String categoryId;

  /// Productos del ticket; con ellos se puede repartir por productos.
  final List<ReceiptItem> items;

  /// Cuenta elegida en la hoja de gasto o el ticket: de ahí salió el dinero.
  final String? accountId;
}

/// Abre el editor para dividir un gasto nuevo (con [draft] o en blanco) o
/// para editar uno existente ([editing], solo su creador). Devuelve true si
/// se guardó; false si se cerró sin guardar (o se borró el gasto).
Future<bool> showSplitEditor(BuildContext context, {SplitDraft? draft, SharedExpense? editing}) async {
  final saved = await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<bool>(
    fullscreenDialog: true,
    builder: (_) => SplitEditorScreen(draft: draft, editing: editing),
  ));
  return saved ?? false;
}

class SplitEditorScreen extends ConsumerStatefulWidget {
  const SplitEditorScreen({super.key, this.draft, this.editing});

  final SplitDraft? draft;
  final SharedExpense? editing;

  @override
  ConsumerState<SplitEditorScreen> createState() => _SplitEditorScreenState();
}

class _SplitEditorScreenState extends ConsumerState<SplitEditorScreen> {
  late final AmountInput _amount = AmountInput()
    ..setMinor(widget.editing?.totalMinor ?? widget.draft?.totalMinor ?? 0);
  /// Cuenta elegida aquí o traída de la hoja de gasto; null = la guardada del
  /// gasto (al editar) o la por defecto.
  late String? _accountId = widget.editing == null ? widget.draft?.accountId : null;

  /// Cuenta guardada para el gasto que se edita (solo en este teléfono).
  String? _storedAccount() {
    final id = widget.editing?.id;
    return id == null ? null : ref.read(walletSettingsProvider).value?.splitAccountIds[id];
  }
  late final _title = TextEditingController(text: widget.editing?.title ?? widget.draft?.title ?? '');
  late DateTime? _date = widget.editing?.date ?? widget.draft?.date;
  late String? _categoryId = widget.editing?.categoryId ?? widget.draft?.categoryId;
  late SplitMode _mode = widget.editing?.mode ?? SplitMode.equal;

  /// Quién pagó y entre quiénes (uids); se completan con el usuario en build.
  String? _paidBy;
  late final Set<String> _with = {...?widget.editing?.participants};

  /// Un campo de texto por persona en el modo Importes.
  final _amountFields = <String, TextEditingController>{};

  /// Personas de cada producto (por posición) en el modo Productos.
  late List<Set<String>> _itemUids = [
    for (final i in widget.editing?.items ?? const <SplitItem>[]) {...i.uids},
  ];

  late bool _editingTotal = _amount.minor == 0;
  bool _saving = false;
  bool _initialized = false;

  bool get _isEditing => widget.editing != null;

  List<SplitItem> get _baseItems => _isEditing
      ? widget.editing!.items
      : [
          for (final i in widget.draft?.items ?? const <ReceiptItem>[])
            SplitItem(name: i.name, amountMinor: i.amountMinor, uids: const []),
        ];

  bool get _hasItems => _baseItems.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
    final e = widget.editing;
    if (e != null && e.mode == SplitMode.amounts) {
      for (final entry in e.shares.entries) {
        _amountFields[entry.key] = TextEditingController(text: (entry.value / 100).toStringAsFixed(2));
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    for (final c in _amountFields.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _fieldFor(String uid) => _amountFields.putIfAbsent(uid, TextEditingController.new);

  /// "12.5" o "12,5" a unidades menores; 0 si no es un número.
  static int _parseMinor(String text) {
    final d = double.tryParse(text.trim().replaceAll(',', '.'));
    if (d == null || d < 0) return 0;
    return (d * 100).round();
  }

  Person _me() {
    final a = ref.read(currentAccountProvider)!;
    return Person(uid: a.uid, name: a.displayName, email: a.email, photoUrl: a.photoUrl);
  }

  /// Tú, tus amigos y, al editar, quienes ya estaban en el gasto.
  List<Person> _everyone(Person me, List<Person> friends) {
    final out = <String, Person>{me.uid: me};
    for (final f in friends) {
      out.putIfAbsent(f.uid, () => f);
    }
    for (final p in widget.editing?.people.values ?? const <Person>[]) {
      out.putIfAbsent(p.uid, () => p);
    }
    return out.values.toList();
  }

  String _label(Person p, String myUid) =>
      p.uid == myUid ? 'Tú' : (p.name.trim().isEmpty ? p.email : p.firstName);

  void _toggleWith(String uid, String myUid) {
    // Quien pagó y tú (el creador) siempre participan: las reglas lo exigen.
    if (uid == _paidBy || uid == myUid) return;
    setState(() {
      if (!_with.remove(uid)) _with.add(uid);
    });
  }

  void _setMode(SplitMode mode, List<String> participants) {
    setState(() {
      _mode = mode;
      if (mode == SplitMode.items && _itemUids.length != _baseItems.length) {
        _itemUids = [for (final _ in _baseItems) {...participants}];
      }
    });
  }

  /// Partes según el modo, o null (con [error]) si todavía no se puede repartir.
  ({Map<String, int>? shares, String? error, List<SplitItem> items}) _compute(List<String> participants) {
    final total = _amount.minor;
    switch (_mode) {
      case SplitMode.equal:
        return (shares: splitEqually(total, participants), error: null, items: const []);
      case SplitMode.amounts:
        final shares = {for (final u in participants) u: _parseMinor(_fieldFor(u).text)};
        return (
          shares: shares,
          error: validateShares(shares, total, currency: _currency()),
          items: const <SplitItem>[],
        );
      case SplitMode.items:
        final items = [
          for (final (i, base) in _baseItems.indexed)
            SplitItem(
              name: base.name,
              amountMinor: base.amountMinor,
              uids: [
                for (final u in participants)
                  if (i < _itemUids.length && _itemUids[i].contains(u)) u,
              ],
            ),
        ];
        final missing = items.any((i) => i.uids.isEmpty);
        if (missing) return (shares: null, error: 'Asigna cada producto a alguien', items: items);
        final shares = splitByItems(items, total);
        return (shares: shares, error: validateShares(shares, total, currency: _currency()), items: items);
    }
  }

  String _currency() =>
      widget.editing?.currency ?? widget.draft?.currency ?? ref.read(walletSettingsProvider).value?.currency ?? 'PEN';

  Future<void> _pickDate(DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 5),
      lastDate: DateTime(current.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickCategory(List<Category> options) async {
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
                        Text(c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.caption.copyWith(
                              color: AppColors.ink,
                              fontWeight: c.id == _categoryId ? FontWeight.w700 : FontWeight.w400,
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

  /// El pago de [uid] sigue valiendo si aún participa, no es quien pagó y su
  /// parte no cambió (si creció, ya no cubre lo que debe).
  bool _keepsSettlement(SharedExpense editing, String uid, List<String> participants, Map<String, int> shares) =>
      participants.contains(uid) &&
      uid != _paidBy &&
      (shares[uid] ?? 0) > 0 &&
      shares[uid] == editing.shares[uid];

  Future<void> _save({
    required Person me,
    required List<Person> everyone,
    required List<String> participants,
    required Map<String, int> shares,
    required List<SplitItem> items,
    required String categoryId,
    required List<Movement> movements,
  }) async {
    final now = ref.read(nowProvider);
    final date = _date ?? now;
    final title = _title.text.trim();
    final editing = widget.editing;
    final newId = const Uuid().v4();

    // Un gasto nuevo puede ser un pago que ya está en la wallet (Google Pay, Apple Pay...).
    Movement? matched;
    if (editing == null) {
      final candidates = findMatchingPayments(
        movements: movements,
        amountMinor: _amount.minor,
        merchant: title,
        date: date,
      );
      if (candidates.isNotEmpty) {
        final (decided, chosen) = await askMatchingPayment(
          context,
          candidates,
          subtitle: 'Ya registraste un gasto parecido. Si es el mismo, lo reemplazamos por tu parte del reparto.',
        );
        if (!decided || !mounted) return;
        matched = chosen;
      }
    }

    // Solo si pagaste tú sale dinero de tu cuenta; se guarda solo en el teléfono.
    // Antes de guardar el gasto, para que su movimiento nazca ya con la cuenta.
    if (_paidBy == me.uid) {
      final selectable = selectableAccounts(ref.read(activeAccountsProvider), currency: _currency());
      final stored = _storedAccount();
      final id = editing?.id ?? newId;
      final split = movements.where((m) => m.id == splitMovementId(id)).firstOrNull;
      // Al editar solo se toca la cuenta si el usuario la cambió en el selector.
      final String? accountId;
      if (editing == null) {
        // Si es un pago que ya estaba en la wallet y no elegiste cuenta, el
        // dinero salió de la cuenta de ese pago (null = la por defecto).
        final wanted = _accountId ?? matched?.accountId;
        accountId = selectable.any((a) => a.id == wanted) ? wanted : resolveAccount(selectable, null)?.id;
      } else {
        accountId = _accountId;
      }
      if (accountId != null && accountId != (stored ?? split?.accountId)) {
        await ref.read(walletActionsProvider).setSplitAccount(id, accountId);
        // Cambiar la cuenta de un reparto ya guardado mueve también su movimiento.
        if (editing != null && split != null && split.accountId != accountId) {
          await ref.read(walletActionsProvider).save(split.copyWith(accountId: accountId));
        }
      }
    }

    if (!mounted) return;
    final byUid = {for (final p in everyone) p.uid: p};
    final people = {for (final u in participants) u: byUid[u]!};
    final expense = editing == null
        ? SharedExpense(
            id: newId,
            createdBy: me.uid,
            paidBy: _paidBy!,
            participants: participants,
            people: people,
            title: title,
            date: DateUtils.isSameDay(date, now) ? now : date,
            currency: _currency(),
            totalMinor: _amount.minor,
            categoryId: categoryId,
            mode: _mode,
            shares: shares,
            items: items,
            updatedAt: now,
          )
        : editing.copyWith(
            paidBy: _paidBy,
            participants: participants,
            people: people,
            title: title,
            date: date,
            totalMinor: _amount.minor,
            categoryId: categoryId,
            mode: _mode,
            shares: shares,
            items: items,
            // Un pago se conserva solo si esa persona sigue debiendo lo mismo.
            settled: {
              for (final e in editing.settled.entries)
                if (_keepsSettlement(editing, e.key, participants, shares)) e.key: e.value,
            },
            updatedAt: now,
          );

    setState(() => _saving = true);
    // Firestore solo responde cuando el servidor confirma: sin red nunca
    // termina. No se espera; los streams ya reflejan el cambio desde la caché.
    final social = ref.read(socialRepositoryProvider);
    fireWrite(
      context,
      editing == null
          ? social.saveExpense(expense)
          // Al editar no se reescribe `settled` entero: solo se quitan los
          // pagos que esta edición invalida, sin pisar los marcados mientras tanto.
          : social.updateExpense(expense, unsettle: {
              for (final k in editing.settled.keys)
                if (!expense.settled.containsKey(k)) k,
            }),
    );
    if (matched != null) {
      // Tu parte nace ya con el rastro del pago que reemplaza (referencia del
      // banco, captura fundida): así una captura o un estado de cuenta posterior
      // la reconocen. La conciliación conserva estos campos.
      final split = reconcileSplitMovements(
        snapshot: ExpensesSnapshot([expense], fromCache: true),
        existing: const [],
        myUid: me.uid,
        categoryIds: {categoryId},
        splitAccountIds: ref.read(walletSettingsRepositoryProvider).read().splitAccountIds,
        now: now,
      ).upsert.firstOrNull;
      if (split != null) {
        await ref.read(walletActionsProvider).save(
              split.copyWith(externalRef: matched.externalRef, pairedCaptureId: matched.pairedCaptureId),
            );
      }
      await ref.read(walletActionsProvider).delete(matched.id);
    }
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar este gasto?'),
        content: const Text('Se borra para todos los que participan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    fireWrite(context, ref.read(socialRepositoryProvider).deleteExpense(widget.editing!.id));
    HapticFeedback.heavyImpact();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(currentAccountProvider);
    if (account == null) return const SheetScaffold(title: 'Dividir gasto', child: SizedBox.shrink());
    final me = _me();
    final now = ref.watch(nowProvider);
    final friends = ref.watch(friendsProvider).value ?? const <Person>[];
    final movements = ref.watch(movementsProvider).value ?? const <Movement>[];
    final all = ref.watch(categoriesProvider).value ?? const <Category>[];
    final options = all.where((c) => c.kind == MovementKind.expense && !c.reserved).toList();
    final categoryId = options.any((c) => c.id == _categoryId) ? _categoryId : options.firstOrNull?.id;
    final category = options.where((c) => c.id == categoryId).firstOrNull;
    final everyone = _everyone(me, friends);
    final currency = _currency();
    final date = _date ?? now;

    if (!_initialized) {
      _initialized = true;
      _paidBy = widget.editing?.paidBy ?? me.uid;
      _with.add(me.uid);
    }
    final participants = [for (final p in everyone) if (_with.contains(p.uid)) p.uid];
    final computed = _compute(participants);
    final shares = computed.shares;
    final canSave = _amount.minor > 0 &&
        participants.length >= 2 &&
        participants.contains(me.uid) &&
        categoryId != null &&
        shares != null &&
        computed.error == null &&
        !_saving;
    final myShare = shares?[me.uid] ?? 0;

    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return SheetScaffold(
      title: _isEditing ? 'Editar gasto compartido' : 'Dividir gasto',
      closeIcon: true,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.ease,
            alignment: Alignment.bottomCenter,
            child: _editingTotal ? AmountKeypad(input: _amount) : const SizedBox(width: double.infinity),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Tu parte: ${Fmt.money(Money(myShare, currency))}',
              style: AppType.headline,
            ),
          ),
          PrimaryButton(
            label: 'Guardar',
            loading: _saving,
            onTap: canSave
                ? () => _save(
                      me: me,
                      everyone: everyone,
                      participants: participants,
                      shares: shares,
                      items: computed.items,
                      categoryId: categoryId,
                      movements: movements,
                    )
                : null,
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            e(Center(
              child: Pressable(
                onTap: () => setState(() => _editingTotal = !_editingTotal),
                highlight: false,
                borderRadius: BorderRadius.circular(16),
                semanticLabel: 'Importe',
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _amount.display(currency),
                    style: AppType.amountHero.copyWith(
                      fontSize: 52,
                      color: _amount.isEmpty ? AppColors.inkTertiary : AppColors.ink,
                    ),
                  ),
                ),
              ),
            )),
            const SizedBox(height: 14),
            e(SurfaceCard(
              radius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: TextField(
                controller: _title,
                style: AppType.body,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Concepto',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            )),
            const SizedBox(height: 8),
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
              onTap: options.isEmpty ? null : () => _pickCategory(options),
            )),
            e(const SectionHeader('Pagó')),
            e(Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in everyone)
                  _PersonChip(
                    key: ValueKey('paid-${p.uid}'),
                    label: _label(p, me.uid),
                    selected: _paidBy == p.uid,
                    onTap: () => setState(() {
                      _paidBy = p.uid;
                      _with.add(p.uid);
                    }),
                  ),
              ],
            )),
            if (_paidBy == me.uid)
              e(Padding(
                padding: const EdgeInsets.only(top: 18),
                child: AccountPicker(
                  selectedId: _accountId ??
                      ref.watch(walletSettingsProvider).value?.splitAccountIds[widget.editing?.id] ??
                      movements.where((m) => m.id == splitMovementId(widget.editing?.id ?? '')).firstOrNull?.accountId,
                  label: '¿De qué cuenta salió?',
                  currency: currency,
                  onChanged: (a) => setState(() => _accountId = a.id),
                ),
              )),
            e(const SectionHeader('Entre')),
            e(Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in everyone)
                  _PersonChip(
                    key: ValueKey('with-${p.uid}'),
                    label: _label(p, me.uid),
                    selected: _with.contains(p.uid),
                    onTap: () => _toggleWith(p.uid, me.uid),
                  ),
              ],
            )),
            const SizedBox(height: 18),
            e(SegmentedControl<SplitMode>(
              values: [SplitMode.equal, SplitMode.amounts, if (_hasItems) SplitMode.items],
              selected: _mode == SplitMode.items && !_hasItems ? SplitMode.equal : _mode,
              label: (m) => switch (m) {
                SplitMode.equal => 'Iguales',
                SplitMode.amounts => 'Importes',
                SplitMode.items => 'Productos',
              },
              onChanged: (m) => _setMode(m, participants),
            )),
            const SizedBox(height: 12),
            if (_mode == SplitMode.amounts)
              for (final p in everyone.where((p) => _with.contains(p.uid)))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SurfaceCard(
                    radius: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                    child: Row(
                      children: [
                        Expanded(child: Text(_label(p, me.uid), style: AppType.body)),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            key: ValueKey('amount-${p.uid}'),
                            controller: _fieldFor(p.uid),
                            textAlign: TextAlign.end,
                            style: AppType.amount,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: '0.00',
                              prefixText: '${Fmt.symbol(currency)} ',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            if (_mode == SplitMode.items)
              for (final (i, item) in _baseItems.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SurfaceCard(
                    radius: 18,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(item.name, style: AppType.body)),
                            Text(Fmt.money(Money(item.amountMinor, currency)), style: AppType.amount),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final p in everyone.where((p) => _with.contains(p.uid)))
                              _PersonChip(
                                key: ValueKey('item-$i-${p.uid}'),
                                label: _label(p, me.uid),
                                selected: i < _itemUids.length && _itemUids[i].contains(p.uid),
                                onTap: () => setState(() {
                                  final set = _itemUids[i];
                                  if (!set.remove(p.uid)) set.add(p.uid);
                                }),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            if (computed.error != null && participants.length >= 2)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(computed.error!, style: AppType.footnote.copyWith(color: AppColors.danger)),
              ),
            if (_isEditing) ...[
              const SizedBox(height: 24),
              PrimaryButton(label: 'Borrar gasto compartido', secondary: true, onTap: _delete),
            ],
          ],
        ),
      ),
    );
  }
}

/// Chip con el nombre de una persona; tocar alterna su selección.
class _PersonChip extends StatelessWidget {
  const _PersonChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        haptic: true,
        highlight: false,
        scale: 0.94,
        borderRadius: BorderRadius.circular(20),
        semanticLabel: label,
        child: AnimatedContainer(
          duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.short,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: ShapeDecoration(
            color: selected ? AppColors.accentSoft : AppColors.surface,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: selected ? AppColors.accent : Colors.transparent, width: 1.5),
            ),
          ),
          child: Text(
            label,
            style: AppType.subhead.copyWith(
              color: AppColors.ink,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
}
