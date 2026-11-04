import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/domain/money.dart';
import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../account/presentation/session_controller.dart';
import '../../capture/domain/process_captures.dart' show accountByDigits;
import '../../wallet/domain/account_balances.dart';
import '../../wallet/domain/wallet_account.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../../wallet/presentation/widgets/account_picker.dart';
import '../data/pdf_text_reader.dart';
import '../data/statement_ai_reader.dart';
import '../data/statement_file_reader.dart';
import '../domain/import_statement.dart';
import '../domain/parse_statement.dart';
import '../domain/statement.dart';

const _oldRowsNotice = 'Estas filas son anteriores a tu saldo inicial: se registran en tu historial pero no cambian el saldo.';

String _plural(int n, String one, String many) => n == 1 ? '$n $one' : '$n $many';

String _kindLabel(RowKind kind) => switch (kind) {
      RowKind.expense => 'Gasto',
      RowKind.income => 'Ingreso',
      RowKind.transfer => 'Transferencia',
      RowKind.fee => 'Comisión',
    };

/// Ajustes → Importar estado de cuenta: cuenta, archivo, contraseña si la pide,
/// columnas si no se reconocen, vista previa e importación. El archivo no se guarda:
/// su copia temporal se borra al leerlo y lo leído vive solo en esta pantalla.
class ImportStatementScreen extends ConsumerStatefulWidget {
  const ImportStatementScreen({super.key});

  @override
  ConsumerState<ImportStatementScreen> createState() => _ImportStatementScreenState();
}

class _ImportStatementScreenState extends ConsumerState<ImportStatementScreen> {
  String? _accountId;
  bool _busy = false;
  String? _error;

  LoadedStatement? _loaded;
  ColumnMapping? _manualColumns;
  ParsedStatement? _parsed;
  List<PreviewRow>? _preview;
  final _selected = <int>{};
  final _overrides = <int, RowChoice>{};

  bool _aiAsked = false;
  bool _aiOn = false;
  ParsedStatement? _aiParsed;

  ({int created, int linked, int? closing, int balance, String currency})? _done;
  bool _adjusted = false;

  WalletAccount? _account(List<WalletAccount> active) => resolveAccount(active, _accountId);

  bool get _needsColumns {
    final loaded = _loaded;
    return loaded != null && _aiParsed == null && loaded.table != null && loaded.mapping == null && _manualColumns == null;
  }

  void _reset() {
    _error = null;
    _loaded = null;
    _manualColumns = null;
    _parsed = null;
    _preview = null;
    _selected.clear();
    _overrides.clear();
    _aiAsked = false;
    _aiOn = false;
    _aiParsed = null;
    _done = null;
    _adjusted = false;
  }

  Future<void> _chooseFile() async {
    final PickedStatement? file;
    try {
      file = await ref.read(statementFilePickerProvider).pick();
    } catch (_) {
      if (mounted) setState(() => _error = kUnreadableMessage);
      return;
    }
    if (file == null || !mounted) return;
    setState(() {
      _reset();
      _busy = true;
    });
    try {
      final loaded = isPdfName(file.name) ? await _openPdf(file) : await loadStatementBytes(file.name, await file.readBytes());
      if (loaded != null) await _show(loaded);
    } on StatementFileException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      // Sin detalles: podrían contener datos del archivo.
      if (mounted) setState(() => _error = kUnreadableMessage);
    } finally {
      await file.discard();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pide la contraseña hasta que abra o se cancele (null). No se guarda en ningún lado.
  Future<LoadedStatement?> _openPdf(PickedStatement file) async {
    final reader = ref.read(pdfTextReaderProvider);
    String? password;
    String? problem;
    while (true) {
      try {
        return await loadStatementPdf(file, reader, password: password, now: ref.read(nowProvider));
      } on PdfPasswordRequired {
        problem = null;
      } on PdfWrongPassword {
        problem = 'Esa contraseña no es correcta.';
      }
      if (!mounted) return null;
      password = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PasswordDialog(problem: problem),
      );
      if (password == null) return null;
    }
  }

  Future<void> _show(LoadedStatement loaded) async {
    final accounts = await ref.read(accountRepositoryProvider).watchAll().first;
    final active = accounts.where((a) => !a.archived).toList();
    // Los dígitos del archivo preseleccionan su cuenta.
    final byDigits = accountByDigits(active, loaded.meta.accountDigits);
    _loaded = loaded;
    if (byDigits != null) _accountId = byDigits.id;
    await _rebuild(resetSelection: true);
  }

  ParsedStatement? _currentParsed(WalletAccount account) {
    final loaded = _loaded;
    if (loaded == null) return null;
    if (_aiParsed != null) return _aiParsed;
    final manual = _manualColumns;
    if (manual != null) return parseStatementTable(loaded.table!, manual, fallbackCurrency: account.currency);
    return loaded.parse(account.currency);
  }

  Future<void> _rebuild({bool resetSelection = false}) async {
    final accounts = await ref.read(accountRepositoryProvider).watchAll().first;
    final movements = await ref.read(movementRepositoryProvider).watchAll().first;
    final active = accounts.where((a) => !a.archived).toList();
    final account = _account(active);
    if (account == null || !mounted) return;
    final parsed = _currentParsed(account);
    if (parsed == null) return;
    final preview = buildPreview(
      rows: parsed.rows,
      account: account,
      accounts: accounts,
      movements: movements,
      holder: _loaded?.meta.holder,
      accountHolder: ref.read(currentAccountProvider)?.displayName,
      now: DateTime.now(),
      overrides: _overrides,
    );
    setState(() {
      final previous = _preview;
      _parsed = parsed;
      _preview = preview;
      if (resetSelection || previous == null || previous.length != preview.length) {
        _selected
          ..clear()
          ..addAll([
            for (var i = 0; i < preview.length; i++)
              if (preview[i].status == RowStatus.fresh) i,
          ]);
      } else {
        // Cambiar el tipo puede enlazar la fila o dejar de hacerlo.
        for (var i = 0; i < preview.length; i++) {
          if (preview[i].status == previous[i].status) continue;
          preview[i].status == RowStatus.fresh ? _selected.add(i) : _selected.remove(i);
        }
      }
    });
  }

  Future<void> _changeAccount(WalletAccount account) async {
    setState(() {
      _accountId = account.id;
      _overrides.clear();
    });
    if (_loaded != null) await _rebuild(resetSelection: true);
  }

  Future<void> _toggleAi(bool on) async {
    if (!on) {
      setState(() {
        _aiOn = false;
        _aiParsed = null;
      });
      _overrides.clear();
      await _rebuild(resetSelection: true);
      return;
    }
    final reader = ref.read(statementAiReaderProvider);
    final loaded = _loaded;
    if (reader == null || loaded == null) return;
    setState(() {
      _aiOn = true;
      _busy = true;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final parsed = await reader.read(loaded.text, now: ref.read(nowProvider));
      if (!mounted) return;
      _aiParsed = parsed;
      _overrides.clear();
      await _rebuild(resetSelection: true);
    } on StatementAiFailed {
      if (!mounted) return;
      setState(() => _aiOn = false);
      messenger?.showSnackBar(const SnackBar(content: Text('No se pudo leer con IA.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeKind(int index, WalletAccount account, List<WalletAccount> active) async {
    final p = _preview![index];
    final others = selectableAccounts(active, currency: account.currency, excludeId: account.id);
    final direction = p.row.isCredit ? 'desde' : 'a';
    final choice = await showModalBottomSheet<RowChoice>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      builder: (context) {
        Widget option(String label, RowChoice value) => ListTile(
              title: Text(label, style: AppType.body),
              onTap: () => Navigator.pop(context, value),
            );
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text('Tipo de movimiento', style: AppType.title2),
              ),
              if (p.row.isCredit)
                option('Ingreso', const RowChoice(RowKind.income))
              else ...[
                option('Gasto', const RowChoice(RowKind.expense)),
                option('Comisión', const RowChoice(RowKind.fee)),
              ],
              for (final other in others)
                option('Transferencia $direction ${other.name}', RowChoice(RowKind.transfer, otherAccountId: other.id)),
              option('Transferencia $direction otra cuenta', const RowChoice(RowKind.transfer)),
            ],
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    _overrides[index] = choice;
    await _rebuild();
  }

  Future<void> _import(WalletAccount account) async {
    final preview = _preview;
    if (preview == null || _busy) return;
    setState(() => _busy = true);
    try {
      final accounts = await ref.read(accountRepositoryProvider).watchAll().first;
      final movements = await ref.read(movementRepositoryProvider).watchAll().first;
      final categories = await ref.read(categoriesProvider.future);
      final upsert = buildImport(
        preview: preview,
        selected: _selected,
        account: account,
        accounts: accounts,
        categories: categories,
        history: movements,
        now: DateTime.now(),
      );
      await ref.read(walletActionsProvider).saveAll(upsert);
      HapticFeedback.mediumImpact();
      final merged = {for (final m in movements) m.id: m, for (final m in upsert) m.id: m}.values.toList();
      final linked = [
        for (var i = 0; i < preview.length; i++)
          if (!_selected.contains(i) && preview[i].link != null) i,
      ].length;
      if (!mounted) return;
      setState(() {
        _done = (
          created: _selected.length,
          linked: linked,
          closing: _parsed?.closingBalanceMinor,
          balance: computeBalances(accounts, merged)[account.id] ?? 0,
          currency: account.currency,
        );
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('No se pudo importar. Inténtalo otra vez.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _adjust(WalletAccount account) async {
    final done = _done;
    final closing = done?.closing;
    if (done == null || closing == null) return;
    final adjustment = makeAdjustment(account: account, currentMinor: done.balance, realMinor: closing, now: DateTime.now());
    if (adjustment != null) await ref.read(walletActionsProvider).save(adjustment);
    HapticFeedback.mediumImpact();
    if (mounted) setState(() => _adjusted = true);
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeAccountsProvider);
    // Sin quien la observe, las categorías no llegarían al importar.
    ref.watch(categoriesProvider);
    final account = _account(active);
    final preview = _preview;
    final ready = _loaded != null && !_needsColumns && preview != null && _parsed != null;

    final Widget child;
    Widget? bottom;
    if (account == null) {
      child = const Center(child: CircularProgressIndicator());
    } else if (_done != null) {
      child = _doneBody(account);
      bottom = PrimaryButton(label: 'Listo', onTap: () => Navigator.maybePop(context));
    } else if (_needsColumns) {
      child = ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          ..._aiSection(rowsFound: false),
          _ColumnChooser(
            table: _loaded!.table!,
            onDone: (mapping) {
              _manualColumns = mapping;
              _rebuild(resetSelection: true);
            },
          ),
        ],
      );
    } else if (ready) {
      child = _previewBody(account, active, preview);
      final linkOnly = [
        for (var i = 0; i < preview.length; i++)
          if (!_selected.contains(i) && preview[i].link != null) i,
      ].length;
      final blocked = _currencyMismatch(account);
      bottom = PrimaryButton(
        label: _selected.isEmpty && linkOnly > 0
            ? 'Enlazar ${_plural(linkOnly, 'transferencia', 'transferencias')}'
            : 'Importar ${_plural(_selected.length, 'movimiento', 'movimientos')}',
        loading: _busy,
        onTap: !blocked && (_selected.isNotEmpty || linkOnly > 0) ? () => _import(account) : null,
      );
    } else {
      child = _startBody();
      bottom = PrimaryButton(label: 'Elegir archivo', loading: _busy, icon: const Icon(LucideIcons.fileUp, size: 18, color: AppColors.onAccent), onTap: _chooseFile);
    }

    return SheetScaffold(title: 'Importar estado de cuenta', bottom: bottom, child: child);
  }

  bool _currencyMismatch(WalletAccount account) {
    final currency = _parsed?.currency;
    return currency != null && currency != account.currency;
  }

  Widget _startBody() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          Entrance(
            child: AccountPicker(selectedId: _accountId, alwaysShow: true, onChanged: _changeAccount),
          ),
          const SizedBox(height: 16),
          Entrance(
            index: 1,
            child: SurfaceCard(
              child: Text(
                'Elige un PDF, un Excel (.xlsx) o un CSV de tu banco. Verás cada fila antes de importarla. El archivo no se guarda.',
                style: AppType.subhead,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _Notice(_error!, danger: true),
          ],
        ],
      );

  List<Widget> _aiSection({required bool rowsFound}) {
    if (ref.watch(statementAiReaderProvider) == null || (_loaded?.text.trim().isEmpty ?? true)) return const [];
    if (rowsFound && !_aiAsked && !_aiOn) {
      return [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _aiAsked = true),
            child: const Text('¿Faltan filas? Leer con IA'),
          ),
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SurfaceCard(
          padding: EdgeInsets.zero,
          child: Pressable(
            key: const ValueKey('useAi'),
            onTap: _busy ? null : () => _toggleAi(!_aiOn),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Usar IA para leer este archivo', style: AppType.body),
                        Text('El texto se envía a Gemini con los números largos ocultos.', style: AppType.footnote),
                      ],
                    ),
                  ),
                  Switch.adaptive(value: _aiOn, onChanged: _busy ? null : _toggleAi),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _previewBody(WalletAccount account, List<WalletAccount> active, List<PreviewRow> preview) {
    final fresh = preview.where((p) => p.status == RowStatus.fresh).length;
    final oldSelected = _selected.any((i) => i < preview.length && !preview[i].movesBalance);
    final mismatch = _currencyMismatch(account);
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccountPicker(selectedId: account.id, alwaysShow: true, onChanged: _changeAccount),
        const SizedBox(height: 12),
        if (mismatch)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Notice(
              'Este archivo está en ${_parsed!.currency} y la cuenta en ${account.currency}. Elige una cuenta en ${_parsed!.currency}.',
              danger: true,
            ),
          ),
        if (preview.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Notice(
              ref.watch(statementAiReaderProvider) == null
                  ? 'No encontramos movimientos en este archivo. Prueba con el estado de cuenta en Excel (.xlsx) o CSV.'
                  : 'No encontramos movimientos en este archivo.',
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              '${_plural(fresh, 'nueva', 'nuevas')} · ${_plural(preview.length - fresh, 'ya registrada', 'ya registradas')}',
              style: AppType.subhead,
            ),
          ),
        if (oldSelected)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: _Notice(_oldRowsNotice),
          ),
        ..._aiSection(rowsFound: preview.isNotEmpty),
      ],
    );
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: preview.length + 2,
      separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 0 : 8),
      itemBuilder: (context, i) {
        if (i == 0) return header;
        if (i == preview.length + 1) {
          return Center(
            child: TextButton(onPressed: _busy ? null : _chooseFile, child: const Text('Elegir otro archivo')),
          );
        }
        final index = i - 1;
        return _RowTile(
          index: index,
          preview: preview[index],
          currency: account.currency,
          selected: _selected.contains(index),
          onSelected: (on) => setState(() => on ? _selected.add(index) : _selected.remove(index)),
          onKind: () => _changeKind(index, account, active),
        );
      },
    );
  }

  Widget _doneBody(WalletAccount account) {
    final done = _done!;
    final closing = done.closing;
    final message = [
      if (done.created > 0 || done.linked == 0)
        done.created == 1 ? 'Se importó 1 movimiento.' : 'Se importaron ${done.created} movimientos.',
      if (done.linked > 0) done.linked == 1 ? 'Se enlazó 1 transferencia.' : 'Se enlazaron ${done.linked} transferencias.',
    ].join(' ');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Entrance(child: SurfaceCard(child: Text(message, style: AppType.headline))),
        // Sin saldo final en el archivo, no hay con qué comparar: no se ofrece ajuste.
        if (closing != null && closing != done.balance && !_adjusted) ...[
          const SizedBox(height: 12),
          Entrance(
            index: 1,
            child: SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'El estado de cuenta dice ${Fmt.money(Money(closing, done.currency))} y el saldo de ${account.name} es ${Fmt.money(Money(done.balance, done.currency))}.',
                    style: AppType.subhead,
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    secondary: true,
                    label: 'Ajustar a ${Fmt.money(Money(closing, done.currency))}',
                    onTap: () => _adjust(account),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_adjusted) ...[
          const SizedBox(height: 12),
          const _Notice('Saldo ajustado.'),
        ],
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.danger = false});
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.all(14),
        color: danger ? AppColors.dangerSoft : AppColors.accentSoft,
        child: Text(text, style: AppType.subhead.copyWith(color: danger ? AppColors.danger : AppColors.ink)),
      );
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.index,
    required this.preview,
    required this.currency,
    required this.selected,
    required this.onSelected,
    required this.onKind,
  });

  final int index;
  final PreviewRow preview;
  final String currency;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onKind;

  @override
  Widget build(BuildContext context) {
    final row = preview.row;
    final fresh = preview.status == RowStatus.fresh;
    final amount = '${row.isCredit ? '+' : '−'}${Fmt.money(Money(row.amountMinor, currency))}';
    final other = preview.other;
    final detail = preview.link != null && other != null
        ? 'Ya está en ${other.name}: se enlaza al importar.'
        : other != null
            ? (row.isCredit ? 'Desde ${other.name}' : 'Hacia ${other.name}')
            : null;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(4, 8, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            key: ValueKey('row_$index'),
            value: selected,
            onChanged: (v) => onSelected(v ?? false),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.description.isEmpty ? 'Sin descripción' : row.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(child: Text(Fmt.dateMedium(row.date), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.footnote)),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 2,
                        child: Text(
                          amount,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: AppType.subhead.copyWith(fontWeight: FontWeight.w600, color: row.isCredit ? AppColors.accent : AppColors.ink),
                        ),
                      ),
                    ],
                  ),
                  if (detail != null) Text(detail, style: AppType.footnote),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: StatusPill(fresh ? 'Nueva' : 'Ya registrada', tone: fresh ? PillTone.accent : PillTone.neutral),
                      ),
                      Pressable(
                        key: ValueKey('kind_$index'),
                        onTap: onKind,
                        borderRadius: BorderRadius.circular(12),
                        semanticLabel: 'Cambiar tipo',
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: StatusPill(_kindLabel(preview.kind), icon: LucideIcons.chevronDown),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Formato desconocido: el usuario dice qué columna es cada dato.
class _ColumnChooser extends StatefulWidget {
  const _ColumnChooser({required this.table, required this.onDone});
  final List<List<String>> table;
  final ValueChanged<ColumnMapping> onDone;

  @override
  State<_ColumnChooser> createState() => _ColumnChooserState();
}

class _ColumnChooserState extends State<_ColumnChooser> {
  int? _date;
  int? _description;
  int? _amount;
  int? _debit;
  int? _credit;

  /// Una fila con fecha, para mostrar un ejemplo de cada columna.
  List<String> get _sample =>
      widget.table.where((r) => r.any((c) => parseStatementDate(c) != null) && r.length > 1).firstOrNull ?? widget.table.firstOrNull ?? const [];

  int get _columns => widget.table.fold(0, (max, r) => r.length > max ? r.length : max);

  Widget _field(String key, String label, int? value, ValueChanged<int?> onChanged, {bool optional = false}) {
    final sample = _sample;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppType.subhead.copyWith(fontWeight: FontWeight.w500)),
          DropdownButton<int?>(
            key: ValueKey('column_$key'),
            isExpanded: true,
            value: value,
            hint: Text(optional ? 'Ninguna' : 'Elegir', style: AppType.body),
            items: [
              if (optional) const DropdownMenuItem<int?>(child: Text('Ninguna')),
              for (var i = 0; i < _columns; i++)
                DropdownMenuItem<int?>(
                  value: i,
                  child: Text(
                    'Columna ${i + 1}${i < sample.length && sample[i].isNotEmpty ? ': ${sample[i]}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => onChanged(v)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final complete = _date != null && _description != null && (_amount != null || _debit != null || _credit != null);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Elige las columnas', style: AppType.headline),
          const SizedBox(height: 4),
          Text('No reconocimos el formato de este archivo. Indica el importe con signo, o el cargo y el abono.', style: AppType.footnote),
          const SizedBox(height: 12),
          _field('date', 'Fecha', _date, (v) => _date = v),
          _field('description', 'Descripción', _description, (v) => _description = v),
          _field('amount', 'Importe con signo', _amount, (v) => _amount = v, optional: true),
          _field('debit', 'Cargo', _debit, (v) => _debit = v, optional: true),
          _field('credit', 'Abono', _credit, (v) => _credit = v, optional: true),
          PrimaryButton(
            label: 'Continuar',
            onTap: complete
                ? () => widget.onDone(ColumnMapping(
                      headerRow: -1,
                      date: _date!,
                      description: _description!,
                      amount: _amount,
                      debit: _debit,
                      credit: _credit,
                    ))
                : null,
          ),
        ],
      ),
    );
  }
}

/// La contraseña vive solo en este diálogo y en la llamada de lectura.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({this.problem});
  final String? problem;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Este PDF tiene contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.problem != null) ...[
              Text(widget.problem!, style: AppType.footnote.copyWith(color: AppColors.danger)),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _controller,
              obscureText: true,
              autofocus: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'Contraseña'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Abrir')),
        ],
      );
}

