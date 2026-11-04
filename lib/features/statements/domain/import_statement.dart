import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../../core/domain/money.dart';
import '../../capture/domain/parse_bank_text.dart' show CaptureDirection;
import '../../capture/domain/process_captures.dart';
import '../../wallet/domain/account_balances.dart';
import '../../wallet/domain/category.dart';
import '../../wallet/domain/default_categories.dart';
import '../../wallet/domain/expense_hints.dart';
import '../../wallet/domain/movement.dart';
import '../../wallet/domain/wallet_account.dart';
import 'statement.dart';

final _ownAccounts = RegExp(r'ctas?\.?\s*propias|cuentas?\s+propias');
final _fee = RegExp(r'impuesto a (?:los|las) (?:creditos|transacciones)|(?<![\p{L}\p{N}])itf(?![\p{L}\p{N}])', unicode: true);
final _prefixed = RegExp(r'^(.+?)\s*-\s*(.+)$');
final _transferText = RegExp(r'^(?:yape|plin)\b|\b(?:transf|trf|cce)\b');

/// El nombre va por prefijo porque el banco lo corta a unas 30 letras.
bool _matchesHolder(String rest, String? holder) {
  if (holder == null) return false;
  final name = normalizeMerchant(holder);
  return rest.length >= 3 && name.startsWith(rest);
}

/// La cuenta propia nombrada como `<cuenta>-<titular>`: el banco escribe así las
/// recargas a tu cuenta en otra entidad. [holder] es el titular del archivo y
/// [accountHolder], el nombre de la cuenta de Google. El nombre de otra persona
/// (`Yape-<persona>`) no es una cuenta propia.
WalletAccount? ownAccountIn(String description, {String? holder, String? accountHolder, required List<WalletAccount> accounts}) {
  final match = _prefixed.firstMatch(normalizeMerchant(description));
  if (match == null) return null;
  final rest = match[2]!;
  if (!_matchesHolder(rest, holder) && !_matchesHolder(rest, accountHolder)) return null;
  final found = accounts.where((a) => normalizeMerchant(a.name) == match[1]).toList();
  return found.length == 1 ? found.first : null;
}

/// Qué es una fila según su texto: transferencia entre cuentas propias, comisión o,
/// si no, gasto o ingreso según el signo.
RowKind classifyDescription(String description, bool isCredit, {String? holder, String? accountHolder, required List<WalletAccount> accounts}) {
  final text = normalizeMerchant(description);
  if (_ownAccounts.hasMatch(text)) return RowKind.transfer;
  if (ownAccountIn(description, holder: holder, accountHolder: accountHolder, accounts: accounts) != null) return RowKind.transfer;
  if (!isCredit && _fee.hasMatch(text)) return RowKind.fee;
  return isCredit ? RowKind.income : RowKind.expense;
}

CaptureDirection _direction(StatementRow row) => row.isCredit ? CaptureDirection.inbound : CaptureDirection.out;

/// Cruza las filas con los movimientos: cada movimiento absorbe a lo sumo una fila,
/// así que las filas iguales se cuentan por multiplicidad. Primero la misma
/// referencia, luego el mismo día y por último ±1 día (un aviso se fecha al
/// recibirlo y el estado de cuenta, al contabilizarlo).
Map<int, Movement> _matchSameAccount(List<StatementRow> rows, WalletAccount account, List<Movement> movements, String defaultId) {
  final free = movements.where((m) => accountSide(m, account.id, defaultId) != null).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  final matched = <int, Movement>{};
  final order = [for (var i = 0; i < rows.length; i++) i]..sort((a, b) => rows[a].date.compareTo(rows[b].date));

  for (final i in order) {
    final ref = rows[i].operationId?.toLowerCase();
    if (ref == null) continue;
    final same = free.where((m) => m.externalRef?.toLowerCase() == ref).firstOrNull;
    if (same != null) {
      matched[i] = same;
      free.remove(same);
    }
  }

  for (final days in const [0, 1]) {
    for (final i in order) {
      if (matched.containsKey(i)) continue;
      final row = rows[i];
      final found = free.where((m) => isDuplicate(
            m,
            accountId: account.id,
            defaultAccountId: defaultId,
            direction: _direction(row),
            amountMinor: row.amountMinor,
            currency: account.currency,
            date: row.date,
            calendarDays: days,
            ref: row.operationId,
          ));
      final first = found.firstOrNull;
      if (first != null) {
        matched[i] = first;
        free.remove(first);
      }
    }
  }
  return matched;
}

/// El lado opuesto ya registrado en [other]: una transferencia a la que le falta
/// esta cuenta, o un ingreso o gasto suelto de una captura o importación anterior.
/// Un gasto repartido o uno manual no se tocan.
bool _isOppositeSide(Movement m, {required WalletAccount other, required StatementRow row, required String defaultId, required Set<String> used}) {
  if (used.contains(m.id)) return false;
  if (!isDuplicate(
    m,
    accountId: other.id,
    defaultAccountId: defaultId,
    direction: row.isCredit ? CaptureDirection.out : CaptureDirection.inbound,
    amountMinor: row.amountMinor,
    currency: other.currency,
    date: row.date,
    calendarDays: 1,
  )) {
    return false;
  }
  switch (m.kind) {
    case MovementKind.transfer:
      return m.toAccountId == null;
    case MovementKind.income:
      return m.origin == MovementOrigin.capture || m.origin == MovementOrigin.statement;
    case MovementKind.expense:
      // Solo el sentido opuesto llega aquí: una recarga (sale de Scotiabank) no se
      // funde con el gasto de un pago desde Dale, que también sale.
      return m.paidMinor == null && (m.origin == MovementOrigin.capture || m.origin == MovementOrigin.statement);
    case MovementKind.adjustment:
      return false;
  }
}

/// [m] convertido en la transferencia completa entre [account] y [other]. Sigue por
/// revisar si lo estaba: enlazarlo no es confirmarlo.
Movement _linked(Movement m, {required WalletAccount account, required WalletAccount other, required bool isCredit}) {
  final from = isCredit ? other : account;
  final to = isCredit ? account : other;
  return m.copyWith(
    kind: MovementKind.transfer,
    categoryId: kNoCategoryId,
    title: '${from.name} → ${to.name}',
    accountId: from.id,
    toAccountId: to.id,
    transferIncoming: false,
  );
}

/// Si cada fila ya está registrada. Con [accounts] se mira también el lado opuesto
/// en la otra cuenta de las transferencias reconocidas.
List<(StatementRow, RowStatus)> classifyRows(
  List<StatementRow> rows,
  WalletAccount account,
  List<Movement> movements, {
  String? defaultAccountId,
  List<WalletAccount> accounts = const [],
  String? holder,
  String? accountHolder,
}) {
  final preview = buildPreview(
    rows: rows,
    account: account,
    accounts: accounts.isEmpty ? [account] : accounts,
    movements: movements,
    defaultAccountId: defaultAccountId,
    holder: holder,
    accountHolder: accountHolder,
    now: DateTime.now(),
  );
  return [for (final p in preview) (p.row, p.status)];
}

/// Lo que el usuario eligió para una fila; [otherAccountId] solo en transferencias.
@immutable
class RowChoice {
  const RowChoice(this.kind, {this.otherAccountId});
  final RowKind kind;
  final String? otherAccountId;
}

/// Una fila de la vista previa.
@immutable
class PreviewRow {
  const PreviewRow({
    required this.row,
    required this.kind,
    required this.status,
    required this.movesBalance,
    this.other,
    this.link,
  });

  final StatementRow row;
  final RowKind kind;
  final RowStatus status;

  /// La otra cuenta de una transferencia reconocida.
  final WalletAccount? other;

  /// El movimiento de la otra cuenta ya enlazado a esta fila, para guardarlo.
  final Movement? link;

  /// Importarla cambia el saldo de la cuenta; si no, solo entra en el historial.
  final bool movesBalance;
}

/// Clasifica las filas para mostrarlas, sin efectos. Con [holder] (del archivo) y
/// [accountHolder] (de Google) se reconocen las cuentas propias.
List<PreviewRow> buildPreview({
  required List<StatementRow> rows,
  required WalletAccount account,
  required List<WalletAccount> accounts,
  required List<Movement> movements,
  required DateTime now,
  String? defaultAccountId,
  String? holder,
  String? accountHolder,
  Map<int, RowChoice> overrides = const {},
}) {
  final defaultId = defaultAccountId ?? defaultAccountOf(accounts)?.id ?? account.id;
  final active = accounts.where((a) => !a.archived).toList();
  final sameAccount = _matchSameAccount(rows, account, movements, defaultId);
  final usedLinks = <String>{for (final m in sameAccount.values) m.id};

  final out = <PreviewRow>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final choice = overrides[i];
    final kind = choice?.kind ?? classifyDescription(row.description, row.isCredit, holder: holder, accountHolder: accountHolder, accounts: active);

    WalletAccount? other;
    if (kind == RowKind.transfer) {
      final candidate = choice != null
          ? active.where((a) => a.id == choice.otherAccountId).firstOrNull
          : ownAccountIn(row.description, holder: holder, accountHolder: accountHolder, accounts: active);
      // Lo recibido en otra moneda no se adivina: queda sin destino registrado.
      if (candidate != null && candidate.id != account.id && candidate.currency == account.currency) other = candidate;
    }

    var status = sameAccount.containsKey(i) ? RowStatus.alreadyThere : RowStatus.fresh;
    Movement? link;
    if (status == RowStatus.fresh && other != null) {
      final opposite = movements.where((m) => _isOppositeSide(m, other: other!, row: row, defaultId: defaultId, used: usedLinks)).firstOrNull;
      if (opposite != null) {
        usedLinks.add(opposite.id);
        status = RowStatus.alreadyThere;
        link = _linked(opposite, account: account, other: other, isCredit: row.isCredit);
      }
    }

    out.add(PreviewRow(
      row: row,
      kind: kind,
      status: status,
      other: other,
      link: link,
      movesBalance: movesBalance(
        _movementOf(row, kind: kind, other: other, account: account, categoryId: kNoCategoryId, now: now),
        account,
        movements,
        defaultId,
      ),
    ));
  }
  return out;
}

Movement _movementOf(
  StatementRow row, {
  required RowKind kind,
  required WalletAccount? other,
  required WalletAccount account,
  required String categoryId,
  required DateTime now,
}) {
  final base = Movement(
    id: 'statement:${const Uuid().v4()}',
    kind: switch (kind) {
      RowKind.expense || RowKind.fee => MovementKind.expense,
      RowKind.income => MovementKind.income,
      RowKind.transfer => MovementKind.transfer,
    },
    amount: Money(row.amountMinor, account.currency),
    categoryId: kind == RowKind.transfer ? kNoCategoryId : categoryId,
    date: row.date,
    createdAt: now,
    title: row.description,
    origin: MovementOrigin.statement,
    accountId: account.id,
    externalRef: row.operationId,
    transferIncoming: kind == RowKind.transfer && other == null && row.isCredit,
  );
  if (kind != RowKind.transfer || other == null) return base;
  return _linked(base, account: account, other: other, isCredit: row.isCredit);
}

String _categoryFor(PreviewRow p, List<Category> categories, List<Movement> history) {
  final expense = categories.where((c) => c.kind == MovementKind.expense && !c.reserved);
  final income = categories.where((c) => c.kind == MovementKind.income && !c.reserved);
  String pick(Iterable<Category> options, List<String> ids) {
    for (final id in ids) {
      if (options.any((c) => c.id == id)) return id;
    }
    return options.firstOrNull?.id ?? kNoCategoryId;
  }

  switch (p.kind) {
    case RowKind.transfer:
      return kNoCategoryId;
    case RowKind.fee:
      final fees = expense.where((c) {
        final name = normalizeMerchant(c.name);
        return name.contains('comision') || name.contains('impuesto') || c.id.contains('fee');
      }).firstOrNull;
      return fees?.id ?? pick(expense, const ['expense_other']);
    case RowKind.expense:
      return suggestCategory(merchant: p.row.description, history: history, categories: expense.toList()) ?? pick(expense, const ['expense_other']);
    case RowKind.income:
      final looksTransfer = _transferText.hasMatch(normalizeMerchant(p.row.description));
      return pick(income, [if (looksTransfer) 'transfer_in', kOtherIncomeCategoryId]);
  }
}

/// Lo que hay que guardar: una fila marcada en [selected] (por índice en [preview])
/// crea un movimiento; una sin marcar que enlaza una transferencia actualiza el
/// otro lado, que de otro modo dejaría sin mover esta cuenta.
List<Movement> buildImport({
  required List<PreviewRow> preview,
  required Set<int> selected,
  required WalletAccount account,
  required List<WalletAccount> accounts,
  required List<Category> categories,
  required List<Movement> history,
  required DateTime now,
}) {
  final out = <Movement>[];
  for (var i = 0; i < preview.length; i++) {
    final p = preview[i];
    if (selected.contains(i)) {
      out.add(_movementOf(p.row, kind: p.kind, other: p.other, account: account, categoryId: _categoryFor(p, categories, history), now: now));
    } else if (p.link != null) {
      out.add(p.link!);
    }
  }
  return out;
}
