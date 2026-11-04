import '../../wallet/domain/apple_pay_link.dart' show parseAmountMinor;
import '../../wallet/domain/expense_hints.dart' show normalizeMerchant;
import 'statement.dart';

// ---------------------------------------------------------------------------
// Fechas e importes
// ---------------------------------------------------------------------------

final _dmyCell = RegExp(r'^\s*(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4}|\d{2})(?!\d)');
final _isoCell = RegExp(r'^\s*(\d{4})-(\d{2})-(\d{2})(?!\d)');
final _serialCell = RegExp(r'^\s*(\d{5})(?:\.\d+)?\s*$');

DateTime? _validDate(int year, int month, int day) {
  final d = DateTime(year, month, day);
  return d.year == year && d.month == month && d.day == day ? d : null;
}

/// Fecha de una celda: `d/m/yyyy` (siempre día primero), ISO o número de serie de
/// Excel (solo el rango de fechas de este siglo: otro número no es una fecha).
DateTime? parseStatementDate(String cell) {
  final dmy = _dmyCell.firstMatch(cell);
  if (dmy != null) {
    final y = int.parse(dmy[3]!);
    return _validDate(y < 100 ? 2000 + y : y, int.parse(dmy[2]!), int.parse(dmy[1]!));
  }
  final iso = _isoCell.firstMatch(cell);
  if (iso != null) return _validDate(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
  final serial = _serialCell.firstMatch(cell);
  if (serial != null) {
    final n = int.parse(serial[1]!);
    if (n >= 36526 && n <= 73050) return DateTime(1899, 12, 30 + n);
  }
  return null;
}

/// Importe con signo en unidades menores. Admite `-45.58`, `45.58-`, `(45.58)`,
/// `−45.58`, `+45.58`, `S/ 1,250.50`, `1.250,50`. Null si no hay un número.
int? parseSignedMinor(String cell) {
  final s = cell.trim();
  if (s.isEmpty || !RegExp(r'\d').hasMatch(s)) return null;
  // Con letras sueltas no es un importe; solo se permiten los símbolos de moneda.
  final bare = s.replaceAll(RegExp(r's/\.?|us\$|\$|€|£|pen|usd|eur', caseSensitive: false), '');
  if (!RegExp(r'^[\s\d.,+\-−()]+$').hasMatch(bare)) return null;
  final minor = parseAmountMinor(bare);
  if (minor == null) return null;
  final negative = RegExp(r'[-−(]').hasMatch(bare);
  return negative ? -minor : minor;
}

final _ignoredDescription = RegExp(r'^(?:sub)?total\b|^sumas?\b|^saldo(?:\s+(?:anterior|inicial|final|actual|al\s+cierre|de\s+cierre))?\b');

/// Totales y saldos que el banco pone entre las filas: no son movimientos.
bool _isSummary(String description) => _ignoredDescription.hasMatch(normalizeMerchant(description));

final _penWords = RegExp(r'\bsoles\b|\bpen\b|s/');
final _usdWords = RegExp(r'\bdolares\b|\busd\b|us\$');

String? _currencyIn(Iterable<String> texts) {
  for (final t in texts) {
    final n = normalizeMerchant(t);
    final pen = _penWords.firstMatch(n)?.start;
    final usd = _usdWords.firstMatch(n)?.start;
    if (pen == null && usd == null) continue;
    if (usd == null) return 'PEN';
    if (pen == null) return 'USD';
    return pen < usd ? 'PEN' : 'USD';
  }
  return null;
}

// ---------------------------------------------------------------------------
// CSV
// ---------------------------------------------------------------------------

List<List<String>> _splitCsv(String text, String delimiter) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch != '"') {
        field.write(ch);
      } else if (i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = false;
      }
    } else if (ch == '"' && field.isEmpty) {
      quoted = true;
    } else if (ch == delimiter) {
      row.add(field.toString().trim());
      field.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString().trim());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString().trim());
    rows.add(row);
  }
  return rows;
}

/// Tabla de un CSV. El separador (coma, punto y coma o tabulador) es el que deja
/// reconocer las columnas o, si ninguno, el que da más campos.
List<List<String>> parseCsvTable(String text) {
  final clean = text.startsWith('\u{FEFF}') ? text.substring(1) : text;
  List<List<String>>? best;
  var bestFields = -1;
  for (final delimiter in const [',', ';', '\t']) {
    final table = _splitCsv(clean, delimiter);
    if (detectColumns(table) != null) return table;
    final fields = table.fold<int>(0, (sum, r) => sum + r.length);
    if (fields > bestFields) {
      best = table;
      bestFields = fields;
    }
  }
  return best ?? const [];
}

// ---------------------------------------------------------------------------
// Tablas
// ---------------------------------------------------------------------------

final _dateHeader = RegExp(r'\b(?:fecha|date|dia|posted)\b');
final _balanceHeader = RegExp(r'\b(?:saldo|balance)\b');
final _opHeader = RegExp(r'\b(?:operacion|nro|numero|referencia|reference|ref|n°|transaction id)\b');
final _debitHeader = RegExp(r'\b(?:cargos?|debe|debit|debitos?|retiros?|salidas?|withdrawals?|paid out|money out)\b');
final _creditHeader = RegExp(r'\b(?:abonos?|haber|credit|creditos?|depositos?|ingresos?|entradas?|deposits?|paid in|money in)\b');
final _amountHeader = RegExp(r'\b(?:importe|monto|amount|valor|value)\b');
final _descriptionHeader = RegExp(r'\b(?:descripcion|concepto|detalles?|glosa|movimiento|description|concept|details?|narrative|merchant|comercio)\b');

/// Busca la fila de títulos en español o inglés. Null si ninguna dice dónde están
/// la fecha, la descripción y el importe: entonces elige el usuario.
ColumnMapping? detectColumns(List<List<String>> table) {
  for (var r = 0; r < table.length; r++) {
    int? date, description, debit, credit, amount, balance, op;
    final cells = table[r];
    for (var c = 0; c < cells.length; c++) {
      final h = normalizeMerchant(cells[c]);
      if (h.isEmpty) continue;
      if (_dateHeader.hasMatch(h)) {
        date ??= c;
      } else if (_balanceHeader.hasMatch(h)) {
        balance ??= c;
      } else if (_opHeader.hasMatch(h)) {
        op ??= c;
      } else if (_debitHeader.hasMatch(h)) {
        debit ??= c;
      } else if (_creditHeader.hasMatch(h)) {
        credit ??= c;
      } else if (_amountHeader.hasMatch(h)) {
        amount ??= c;
      } else if (_descriptionHeader.hasMatch(h)) {
        description ??= c;
      }
    }
    if (date == null || description == null) continue;
    if (amount == null && debit == null && credit == null) continue;
    return ColumnMapping(
      headerRow: r,
      date: date,
      description: description,
      debit: debit,
      credit: credit,
      amount: amount,
      balance: balance,
      operationId: op,
    );
  }
  return null;
}

String _cell(List<String> row, int? column) => column != null && column >= 0 && column < row.length ? row[column].trim() : '';

/// Las filas que tienen fecha, descripción e importe. Lo demás (vacías, títulos,
/// totales, avisos legales) no es un movimiento y se ignora.
ParsedStatement parseStatementTable(List<List<String>> table, ColumnMapping mapping, {required String fallbackCurrency}) {
  final rows = <StatementRow>[];
  final balances = <int>[];
  for (var r = mapping.headerRow + 1; r < table.length; r++) {
    final cells = table[r];
    final date = parseStatementDate(_cell(cells, mapping.date));
    if (date == null) continue;
    final description = _cell(cells, mapping.description);
    if (_isSummary(description)) continue;

    int? signed;
    if (mapping.amount != null) signed = parseSignedMinor(_cell(cells, mapping.amount));
    if (signed == null || signed == 0) {
      final debit = parseSignedMinor(_cell(cells, mapping.debit));
      final credit = parseSignedMinor(_cell(cells, mapping.credit));
      if (debit != null && debit != 0) {
        signed = -debit.abs();
      } else if (credit != null && credit != 0) {
        signed = credit.abs();
      }
    }
    if (signed == null || signed == 0) continue;

    rows.add(StatementRow(
      date: date,
      description: description,
      amountMinor: signed.abs(),
      isCredit: signed > 0,
      operationId: _cell(cells, mapping.operationId).isEmpty ? null : _cell(cells, mapping.operationId),
    ));
    final balance = parseSignedMinor(_cell(cells, mapping.balance));
    if (mapping.balance != null && balance != null) balances.add(balance);
  }

  // Con todas las filas con saldo, el último cronológico: el archivo puede ir al revés.
  int? closing;
  if (balances.isNotEmpty && balances.length == rows.length) {
    final newestFirst = rows.first.date.isAfter(rows.last.date);
    closing = newestFirst ? balances.first : balances.last;
  }

  final header = mapping.headerRow < 0 ? const <List<String>>[] : table.take(mapping.headerRow + 1);
  final headerAmount = mapping.headerRow < 0
      ? null
      : _currencyIn([
          _cell(table[mapping.headerRow], mapping.amount),
          _cell(table[mapping.headerRow], mapping.debit),
          _cell(table[mapping.headerRow], mapping.credit),
        ]);
  return ParsedStatement(
    rows: rows,
    closingBalanceMinor: closing,
    currency: headerAmount ?? _currencyIn(header.map((r) => r.join(' '))) ?? fallbackCurrency,
  );
}

// ---------------------------------------------------------------------------
// Cabecera
// ---------------------------------------------------------------------------

const _labels = r'titular|cliente|cuenta|desde|hasta|periodo|moneda|fecha';
final _holderRe = RegExp('(?:^|\\s)(?:titular|cliente)\\s*:\\s*(.+?)(?=\\s{2,}|\\s(?:$_labels)\\s*:|\$)', caseSensitive: false);
final _accountRe = RegExp(r'(?:^|\s)(?:cuenta|cta\.?)\s*:\s*(.+)$', caseSensitive: false);
final _maskedDigits = RegExp(r'[*x•·]{2,}[\s-]*(\d{3,4})\b', caseSensitive: false);
final _trailingDigits = RegExp(r'(\d{4,})\s*$');
final _fromRe = RegExp(r'(?:^|\s)desde\s*:\s*(\S+)', caseSensitive: false);
final _toRe = RegExp(r'(?:^|\s)hasta\s*:\s*(\S+)', caseSensitive: false);

/// Titular, dígitos de la cuenta y periodo de las filas anteriores a los títulos.
StatementMeta readStatementMeta(List<List<String>> table) {
  final mapping = detectColumns(table);
  final top = mapping == null ? table.take(40) : table.take(mapping.headerRow);
  return _metaOfLines(top.map((r) => r.where((c) => c.trim().isNotEmpty).join('  ').replaceFirst(RegExp(r':\s{2,}'), ': ')));
}

/// Lo mismo, en el texto de un PDF.
StatementMeta readStatementMetaText(String text) => _metaOfLines(text.split(RegExp(r'\r?\n')).take(40));

StatementMeta _metaOfLines(Iterable<String> lines) {
  String? holder;
  String? digits;
  DateTime? from;
  DateTime? to;
  for (final line in lines) {
    holder ??= _holderRe.firstMatch(line)?[1]?.trim();
    final account = _accountRe.firstMatch(line)?[1];
    if (account != null) {
      digits ??= _maskedDigits.firstMatch(account)?[1];
      digits ??= _trailingDigits.firstMatch(account)?[1];
    }
    digits ??= _maskedDigits.firstMatch(line)?[1];
    final fromCell = _fromRe.firstMatch(line)?[1];
    if (fromCell != null) from ??= parseStatementDate(fromCell);
    final toCell = _toRe.firstMatch(line)?[1];
    if (toCell != null) to ??= parseStatementDate(toCell);
  }
  return StatementMeta(holder: holder, accountDigits: digits, from: from, to: to);
}

// ---------------------------------------------------------------------------
// Texto de un PDF
// ---------------------------------------------------------------------------

const _monthNames = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic'];
const _monthAlt = r'ene(?:ro)?|feb(?:rero)?|mar(?:zo)?|abr(?:il)?|may(?:o)?|jun(?:io)?|jul(?:io)?|ago(?:sto)?|set(?:iembre)?|sep(?:tiembre)?|oct(?:ubre)?|nov(?:iembre)?|dic(?:iembre)?';

final _numericDate = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})(?:[/\-.](\d{4}|\d{2}))?(?![\d/.])');
final _wordDate = RegExp('^(\\d{1,2})[\\s\\-/]*(?:de\\s+)?($_monthAlt)\\.?(?:[\\s\\-/]*(?:de\\s+)?(\\d{4}))?(?![a-z])', caseSensitive: false);

const _amountToken = r'[-+−(]?\s?(?:s/\.?\s?|us\$\s?|\$\s?|pen\s|usd\s)?[-−]?(?:\d{1,3}(?:[.,]\d{3})+|\d+)[.,]\d{2}\)?-?(?:\s?(?:cr|db)\b)?';
final _trailingAmounts = RegExp('^(.*?)((?:\\s+$_amountToken)+)\\s*\$', caseSensitive: false);
final _oneAmount = RegExp(_amountToken, caseSensitive: false);

final _openingBalance = RegExp('^\\s*saldo\\s+(?:anterior|inicial)\\b.*?\\s($_amountToken)\\s*\$', caseSensitive: false);
final _closingBalance = RegExp('^\\s*saldo\\s+(?:final|actual|al\\s+cierre|de\\s+cierre)\\b.*?\\s($_amountToken)\\s*\$', caseSensitive: false);

/// Un importe sin signo en un texto sin saldos: estas palabras dicen que entró.
final _creditWords = RegExp(r'\b(?:abono|deposito|haberes|sueldo|remuneracion|devolucion|reembolso|recibid[oa]|intereses?)\b|^(?:yape|plin)-');

({int minor, bool? credit}) _readToken(String token) {
  final lower = token.toLowerCase().trim();
  final minor = parseAmountMinor(lower.replaceAll(RegExp(r'cr|db|pen|usd'), '')) ?? 0;
  if (RegExp(r'[-−(]').hasMatch(lower) || lower.endsWith('db')) return (minor: minor, credit: false);
  if (lower.startsWith('+') || lower.endsWith('cr')) return (minor: minor, credit: true);
  return (minor: minor, credit: null);
}

/// La fecha al inicio de [line], con el resto de la línea. Sin año, el que
/// corresponda: se pasa de diciembre a enero una sola vez y hacia adelante.
({DateTime date, int month, bool hasYear, String rest})? _leadingDate(String line, int year) {
  final trimmed = line.trimLeft();
  final numeric = _numericDate.firstMatch(trimmed);
  if (numeric != null) {
    final y = numeric[3] == null ? null : int.parse(numeric[3]!);
    final date = _validDate(y == null ? year : (y < 100 ? 2000 + y : y), int.parse(numeric[2]!), int.parse(numeric[1]!));
    if (date == null) return null;
    return (date: date, month: date.month, hasYear: y != null, rest: trimmed.substring(numeric.end));
  }
  final word = _wordDate.firstMatch(trimmed);
  if (word == null) return null;
  final name = word[2]!.toLowerCase().substring(0, 3);
  final month = _monthNames.indexOf(name == 'sep' ? 'set' : name) + 1;
  final y = word[3] == null ? null : int.parse(word[3]!);
  final date = _validDate(y ?? year, month, int.parse(word[1]!));
  if (date == null) return null;
  return (date: date, month: month, hasYear: y != null, rest: trimmed.substring(word.end));
}

/// Filas de un texto línea a línea: `fecha descripción importe [saldo]`. [year] es
/// el del inicio del periodo y se usa con las fechas que no traen año.
ParsedStatement parseStatementText(String text, {required int year, required String fallbackCurrency}) {
  final lines = text.split(RegExp(r'\r?\n'));
  final rows = <StatementRow>[];
  var currentYear = year;
  int? lastMonth;
  int? previousBalance;
  int? stated;
  int? lastBalance;

  for (final raw in lines) {
    final line = raw.replaceAll('\u{00A0}', ' ').trim();
    if (line.isEmpty) continue;

    final closing = _closingBalance.firstMatch(line);
    if (closing != null) {
      final t = _readToken(closing[1]!);
      stated = t.credit == false ? -t.minor : t.minor;
      continue;
    }
    final opening = _openingBalance.firstMatch(line);
    if (opening != null) {
      final t = _readToken(opening[1]!);
      previousBalance = t.credit == false ? -t.minor : t.minor;
      continue;
    }

    var found = _leadingDate(line, currentYear);
    if (found == null) continue;
    if (!found.hasYear && lastMonth != null && found.month < lastMonth && lastMonth - found.month >= 6) {
      currentYear++;
      found = _leadingDate(line, currentYear)!;
    }
    lastMonth = found.month;
    if (found.hasYear) currentYear = found.date.year;

    // Una segunda fecha (operación y proceso) no es parte de la descripción.
    var rest = found.rest.trimLeft();
    final second = _leadingDate(rest, currentYear);
    if (second != null) rest = second.rest;

    final amounts = _trailingAmounts.firstMatch(rest);
    if (amounts == null) continue;
    final description = amounts[1]!.trim();
    if (description.isEmpty || _isSummary(description)) continue;
    final tokens = _oneAmount.allMatches(amounts[2]!).map((m) => _readToken(m[0]!)).toList();

    final amount = tokens.first;
    final balance = tokens.length >= 2 ? tokens.last : null;
    final balanceMinor = balance == null ? null : (balance.credit == false ? -balance.minor : balance.minor);
    if (amount.minor == 0) continue;

    final bool isCredit;
    if (amount.credit != null) {
      isCredit = amount.credit!;
    } else if (balanceMinor != null && previousBalance != null && balanceMinor != previousBalance) {
      isCredit = balanceMinor > previousBalance;
    } else {
      isCredit = _creditWords.hasMatch(normalizeMerchant(description));
    }
    if (balanceMinor != null) {
      previousBalance = balanceMinor;
      lastBalance = balanceMinor;
    }

    rows.add(StatementRow(date: found.date, description: description, amountMinor: amount.minor, isCredit: isCredit));
  }

  return ParsedStatement(
    rows: rows,
    closingBalanceMinor: stated ?? lastBalance,
    currency: _currencyIn(lines.take(30)) ?? fallbackCurrency,
  );
}

/// Lee el texto de un PDF eligiendo el año: el del inicio del periodo o, sin él, el
/// actual; un movimiento no puede estar en el futuro, así que entonces es el anterior.
ParsedStatement parseStatementPdfText(String text, {required DateTime now, required String fallbackCurrency}) {
  final year = readStatementMetaText(text).from?.year ?? now.year;
  final first = parseStatementText(text, year: year, fallbackCurrency: fallbackCurrency);
  final limit = now.add(const Duration(days: 1));
  if (!first.rows.any((r) => r.date.isAfter(limit))) return first;
  return parseStatementText(text, year: year - 1, fallbackCurrency: fallbackCurrency);
}

// ---------------------------------------------------------------------------
// Texto para la IA
// ---------------------------------------------------------------------------

/// Lo que se respeta tal cual: fechas e importes con decimales o miles.
final _protectedOrDigits = RegExp(
  r'(?<!\d)\d{1,2}[/-]\d{1,2}[/-](?:\d{4}|\d{2})(?!\d)|' // fecha
  r'(?<!\d)\d{4}-\d{2}-\d{2}(?!\d)|' // fecha ISO
  r'(?<![\d.,])\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?(?![\d.,]*\d)|' // importe con miles
  r'(?<![\d.,])\d+[.,]\d{1,2}(?![\d.,]*\d)|' // importe con decimales
  r'(?<sequence>\d+(?:[ -]\d+)*)', // números, quizá con separadores
);

/// Tapa los números de 8 o más cifras, con o sin espacios o guiones (cuentas, CCI,
/// tarjetas, DNI, referencias), sin tocar importes ni fechas.
String maskSensitive(String text) => text.replaceAllMapped(_protectedOrDigits, (m) {
      final found = m as RegExpMatch;
      var sequence = found.namedGroup('sequence');
      if (sequence == null) return m[0]!;
      // El último grupo pegado a ".50" o "/09" es parte de un importe o una fecha.
      var tail = '';
      final after = m.end < text.length ? text.substring(m.end) : '';
      if (RegExp(r'^[.,/]\d').hasMatch(after)) {
        final cut = sequence.lastIndexOf(RegExp(r'[ -]'));
        if (cut >= 0) {
          tail = sequence.substring(cut);
          sequence = sequence.substring(0, cut);
        } else {
          return sequence;
        }
      }
      final digits = RegExp(r'\d').allMatches(sequence).length;
      if (digits < 8) return '$sequence$tail';
      return '${sequence.replaceAll(RegExp(r'\d'), '*')}$tail';
    });
