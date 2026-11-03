import 'package:meta/meta.dart';

import '../../wallet/domain/apple_pay_link.dart';

enum CaptureDirection { out, inbound }

/// Lo que se entendió de un aviso, correo o SMS bancario.
@immutable
class ParsedBankText {
  const ParsedBankText({
    required this.amountMinor,
    required this.currency,
    required this.direction,
    this.counterparty,
    this.date,
    this.operationId,
    this.accountDigits,
    this.toAccountDigits,
    this.isTransfer = false,
  });

  final int amountMinor;
  final String currency;
  final CaptureDirection direction;

  /// Comercio o persona al otro lado.
  final String? counterparty;

  /// Fecha escrita en el texto (null si no trae: se usa la de recepción).
  final DateTime? date;
  final String? operationId;

  /// Últimos dígitos de la cuenta o tarjeta propia usada.
  final String? accountDigits;

  /// Últimos dígitos de la cuenta de destino ("a la cuenta ****5678").
  final String? toAccountDigits;

  /// El texto habla de un envío o transferencia (no de una compra).
  final bool isTransfer;
}

/// Lo que hay que tapar para que un número nunca se lea como importe.
const _mask = '§';

const _token = r'[a-z0-9-]*\d[a-z0-9-]*(?![a-z0-9-]|[.,]\d)';
const _months = 'enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre';

final _idPrimary = RegExp('\\bid\\s+de\\s+(?:la\\s+)?(?:operacion|transaccion)\\s*[:#]?\\s*($_token)');
final _idGeneric = RegExp(
  '(?<![a-z0-9])(?:n[°º]|nro\\.?|numero|codigo|cod\\.?|ref\\.?|referencia|comprobante|constancia)\\s*'
  '(?:de\\s+)?(?:la\\s+)?(?:operacion|transaccion|referencia)?\\s*[:#]?\\s*($_token)',
);
final _idOperation = RegExp(
  '(?<!(?:monto|importe|total)\\s(?:de\\s)?(?:la\\s|el\\s)?)\\b(?:operacion|transaccion)\\s*(?:n[°º]|nro\\.?|numero)?\\s*[:#]?\\s*($_token)',
);
final _idExternal = RegExp('\\bid\\s+externo\\s*[:#]?\\s*($_token)');

final _isoDate = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b');
final _dmyDate = RegExp(r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{4}|\d{2})\b');
final _wordDate = RegExp('\\b(\\d{1,2})\\s+de\\s+($_months)(?:\\s+(?:de|del)\\s+(\\d{4}))?');
final _dmDate = RegExp(r'\b(?:el|fecha:?)\s+(\d{1,2})/(\d{1,2})\b(?![/\d])');
final _timeAfter = RegExp(r'^\D{0,8}?(\d{1,2}):(\d{2})(?::\d{2})?(?:\s*([ap])\.?\s?m)?');

final _maskedDigits = RegExp(r'[*x•·]{2,}[\s-]*(\d{3,4})\b');
final _endsInDigits = RegExp(r'termina(?:da|do)?\s+en\s+(\d{3,4})\b');
final _plainAccountDigits = RegExp(r'\b(?:cuenta|tarjeta|cta\.?|tarj\.?)\s*(?:n[°º]|nro\.?)?\s*:?\s*(\d{4})\b(?![.,]\d)');

/// Campos cuyos dígitos jamás son un importe.
final _sensitive = <RegExp>[
  RegExp(r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'),
  RegExp(r'\bcci\b\s*[:#]?\s*(?:n/a|[\d\s-]{6,})'),
  _idExternal,
  _idPrimary,
  RegExp(r'\bid\b\s*[:#]\s*[a-z0-9-]+'),
  RegExp(r'(?<![a-z0-9])(?:n[°º]\s*(?:de\s+)?)?(?:telefono|celular|cel\.?|tel\.?)\s*[:#]?\s*(?:n/a|\+?[\d\s-]{6,})'),
  _idGeneric,
  _idOperation,
  _isoDate,
  _dmyDate,
  _wordDate,
  RegExp(r'\b\d{1,2}/\d{1,2}\b'),
  RegExp(r'\b\d{1,2}:\d{2}(?::\d{2})?(?:\s*[ap]\.?\s?m\.?)?'),
  _maskedDigits,
  _endsInDigits,
  RegExp(r'\b(?:cuenta|tarjeta|cta\.?|tarj\.?)\s*(?:n[°º]|nro\.?)?\s*:?\s*\d[\d -]{2,}(?![.,]\d)'),
  RegExp(r'\b9\d{8}\b(?![.,]\d)'),
];

const _number = r'\d(?:[\d.,]*\d)?';
const _symbols = r'us\$|mx\$|col\$|ar\$|clp\$|r\$|s\s?/\.?|pen|usd|eur|mxn|cop|ars|clp|gbp|brl|€|£|\$';
const _pastVerbs = 'pagaste|enviaste|recibiste|transferiste|compraste|consumiste|retiraste|depositaste|yapeaste|plineaste|'
    'realizaste|hiciste|efectuaste|has (?:pagado|enviado|recibido|transferido|realizado|hecho)|'
    'te (?:envio|enviaron|transfirio|transfirieron|yapeo|yapearon|plineo|plinearon|pago|pagaron|deposito|depositaron|abono|abonaron|llego)|'
    'abonamos|depositamos|se (?:abono|deposito|acredito|realizo|debito|cargo)';
const _nouns = 'total|consumo|compra|pago|retiro|transferencia|envio|abono|deposito|cargo|debito|ingreso|reembolso|devolucion|yape|plin';

final _prefixAmount = RegExp('(?<![a-z0-9])($_symbols)\\s*(-?)\\s*($_number)(?![\\d%])');
final _suffixAmount = RegExp('(?<![\\d.,])($_number)\\s*(soles|sol|dolares|euros|pen|usd|eur|mxn|cop|ars|clp|gbp|brl)(?![a-z0-9])');
final _keywordAmount = RegExp(
  '\\b(?:monto|importe|total)(?:\\s+(?:de\\s+)?(?:la\\s+|el\\s+)?(?:operacion|transaccion|pago|compra|envio|transferencia|consumo|retiro))?'
  '\\s*(?:de|por)?\\s*[:=]?\\s*-?\\s*($_number)(?![\\d%])',
);
final _verbAmount = RegExp('\\b(?:$_pastVerbs)\\s*(?:de|por)?\\s*[:=]?\\s*(\\d[\\d.,]*[.,]\\d{2})(?![\\d%])');
final _onlyAmount = RegExp(r'^(?:\d{1,3}(?:[.,]\d{3})*[.,]\d{2}|\d+[.,]\d{2})$');

final _verbRe = RegExp('\\b(?:$_pastVerbs)\\b');
final _opRe = RegExp('\\b(?:$_pastVerbs|monto|importe)\\b');
final _montoRe = RegExp(r'\b(?:monto|importe)\b');
final _nounRe = RegExp('\\b(?:$_nouns)\\b');
final _anyOpRe = RegExp('\\b(?:$_pastVerbs|monto|importe|$_nouns|recibid[oa]s?|pagad[oa]s?|enviad[oa]s?|transferid[oa]s?|abonad[oa]s?)\\b');

/// Antes del importe (tras el último verbo): no es el importe de la operación.
final _discardBefore = RegExp(
  r'\b(?:saldos?|disponibles?|comision(?:es)?|itf|impuestos?|mantenimiento|membresia|linea de credito|limite|minimo|'
  r'descuento|dscto|cashback|premio|bono|sorteo|gana|ganaste)\b',
);
final _discardAdjacent = RegExp(r'\b(?:desde|hasta)\s*$');
final _discardAfter = RegExp(
  r'^\s*(?:(?:de|por|como|en|al)\s+(?:saldos?|comision(?:es)?|itf|impuestos?|mantenimiento|descuento|dscto|cashback|bono)\b|'
  r'(?:de\s+saldo\s+)?disponibles?\b|\(\s*(?:comision|itf|impuesto))',
);

/// Lo que no ocurrió (rechazado, futuro) o no es una operación (publicidad, claves).
final _blockers = RegExp(
  r'rechazad|declinad|denegad|fallid|\bno (?:se )?(?:pudo|pudimos|fue posible|procesad|realizad)|no exitos|revertid|anulad|extornad|'
  r'codigo de (?:verificacion|seguridad)|clave dinamica|\botp\b|para (?:autorizar|confirmar|aprobar)|\bvence\b|vencimiento|'
  r'\brecuerda\b|recordatorio|programad|proxim[oa] (?:pago|cobro|cargo)|aprovecha|\boferta|promocion|sorteo|prestamo|pre-?aprobad|'
  r'\bsolicita\b|te regalamos|\bgana\b|\bganar\b',
);

final _lemonPhrase = RegExp(r'realizaste un envio exitoso de\s');

final _outPaid = RegExp(r'tu pago[^\n!?;]{0,30}recibid|recibimos tu pago');
final _outVerbs = RegExp(
  r'\b(?:pagaste|enviaste|transferiste|compraste|consumiste|retiraste|yapeaste|plineaste|realizaste|hiciste|efectuaste|'
  r'has (?:pagado|enviado|transferido|realizado|hecho)|se (?:realizo|debito|cargo))\b',
);
final _inVerbs = RegExp(
  r'\b(?:recibiste|has recibido|te (?:envio|enviaron|transfirio|transfirieron|yapeo|yapearon|plineo|plinearon|pago|pagaron|deposito|depositaron|abono|abonaron|llego)|'
  r'abonamos|depositamos|se (?:abono|deposito|acredito)|recibid[oa]s?)\b',
);
final _outNouns = RegExp(r'\b(?:consumo|compra|pago|retiro|transferencia|envio|cargo|debito|pagad[oa]s?|enviad[oa]s?|transferid[oa]s?)\b');
final _inNouns = RegExp(r'\b(?:abono|abonad[oa]s?|deposito|ingreso|reembolso|devolucion)\b');

final _transferWords = RegExp(r'\b(?:transfer\w*|enviaste|envio|te envi\w+|yape\w*|plin\w*|cce|cci)\b');
final _purchaseWords = RegExp(r'\b(?:compra|compraste|consumo|consumiste)\b');

final _counterpartyLabel = RegExp(r'\b(?:nombre|destinatario|beneficiario|comercio|establecimiento|para)\s*:\s*');
final _otherPartyLabel = RegExp(r'\b(?:nombre|destinatario|beneficiario|comercio|establecimiento|para|entidad|banco(?:\s+destino)?)\s*:\s*');
final _fieldEnd = RegExp(r'[\n§]|\s(?:n[°º]|nro\b|cci\b|entidad\s*:|nombre\s*:|id\s|fecha|monto|importe|banco\s*:|telefono|celular|saldo|comision)');
final _sentByName = RegExp(r'([^\n.,;:!?§()]{2,50}?)\s+te\s+(?:envio|enviaron|transfirio|yapeo|plineo|pago|deposito|abono)\b');
final _valueEnd = RegExp(r'[.,;:!?\n§(]|\s(?:con|el|por|desde|hoy|usando|mediante|via|y|en|a las|de tu|de la)\b');
final _ownAccountPrefix = RegExp(r'^(?:tu|mi|la|su)\s+(?:cuenta|tarjeta)\s+(?:de\s+)?');
final _notAParty = RegExp(r'^(?:tu|su|mi|un|una|cuenta|tarjeta|linea|cuotas?)\b|^(?:la|el)\s+(?:cuenta|tarjeta|app|aplicacion|fecha)\b|^(?:la|el|los|las)$|^n/a$|@');
final _partyEdges = RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}.]+$', unicode: true);
final _hasLetter = RegExp(r'\p{L}', unicode: true);

/// Minúsculas, sin acentos ni espacios raros, con la misma longitud: una posición
/// en este texto es la misma posición en el original.
String _fold(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñ';
  const to = 'aaaaeeeeiiiioooouuuun';
  final b = StringBuffer();
  for (final unit in s.codeUnits) {
    final ch = String.fromCharCode(unit);
    final lower = ch.toLowerCase();
    final c = lower.length == 1 ? lower : ch;
    final i = from.indexOf(c);
    b.write(i == -1 ? c : to[i]);
  }
  return b.toString();
}

String _plainSpaces(String s) => s.replaceAll(RegExp('[   ]'), ' ');

/// [raw] con los campos sensibles tapados, buscando sobre su versión [_fold].
String _maskFields(String raw, Iterable<RegExp> patterns) {
  final out = raw.split('');
  final folded = _fold(raw);
  for (final p in patterns) {
    for (final m in p.allMatches(folded)) {
      out.fillRange(m.start, m.end, _mask);
    }
  }
  return out.join();
}

class _Amount {
  const _Amount({required this.start, required this.numStart, required this.end, required this.minor, this.currency});

  final int start;
  final int numStart;
  final int end;
  final int minor;
  final String? currency;
}

_Amount? _amount(int start, int numStart, int end, String number, String? currency) {
  if (number.replaceAll(RegExp(r'\D'), '').length > 12) return null;
  final minor = parseAmountMinor(number);
  if (minor == null || minor <= 0) return null;
  return _Amount(start: start, numStart: numStart, end: end, minor: minor, currency: currency);
}

/// Importes con moneda, o bien sin ella si van justo tras "monto" o un verbo. Un
/// número suelto no es un importe.
List<_Amount> _findAmounts(String folded, String fallback) {
  final out = <_Amount>[];
  bool overlaps(int start, int end) => out.any((a) => start < a.end && a.start < end);

  void add(Match m, int group, String? currency) {
    final number = m[group]!;
    final numStart = m.end - number.length;
    if (overlaps(numStart, m.end)) return;
    final a = _amount(numStart, numStart, m.end, number, currency);
    if (a != null) out.add(a);
  }

  for (final m in _prefixAmount.allMatches(folded)) {
    final token = m[1]!.replaceAll(RegExp(r'[\s.]'), '');
    final number = m[3]!;
    final a = _amount(m.start, m.end - number.length, m.end, number, currencyOfToken(token, fallback: fallback));
    if (a != null) out.add(a);
  }
  for (final m in _suffixAmount.allMatches(folded)) {
    final word = m[2]!;
    final currency = switch (word) {
      'soles' || 'sol' => 'PEN',
      'dolares' => 'USD',
      'euros' => 'EUR',
      _ => word.toUpperCase(),
    };
    if (overlaps(m.start, m.end)) continue;
    final a = _amount(m.start, m.start, m.end, m[1]!, currency);
    if (a != null) out.add(a);
  }
  for (final m in _keywordAmount.allMatches(folded)) {
    add(m, 1, null);
  }
  for (final m in _verbAmount.allMatches(folded)) {
    add(m, 1, null);
  }
  return out..sort((a, b) => a.start.compareTo(b.start));
}

int _sentenceStart(String folded, int from, int to) {
  var start = from;
  for (final m in RegExp(r'[!?;\n…]|\.\s').allMatches(folded.substring(from, to))) {
    start = from + m.end;
  }
  return start;
}

int _sentenceEnd(String folded, int from) {
  final m = RegExp(r'[!?;\n…]|\.(?:\s|$)').firstMatch(folded.substring(from));
  return m == null ? folded.length : from + m.start;
}

String _beforeWindow(String folded, List<_Amount> all, int i) {
  final a = all[i];
  final prevEnd = i == 0 ? 0 : all[i - 1].end;
  var start = _sentenceStart(folded, prevEnd, a.start);
  if (a.start - start > 80) start = a.start - 80;
  return folded.substring(start, a.start);
}

bool _discarded(String window, String after) {
  if (_discardAdjacent.hasMatch(window)) return true;
  if (_discardAfter.hasMatch(after)) return true;
  final last = _opRe.allMatches(window).lastOrNull;
  return _discardBefore.hasMatch(last == null ? window : window.substring(last.end));
}

/// Cuánto se parece a un importe de operación por lo que tiene delante.
int _rank(String window) {
  if (_verbRe.hasMatch(window)) return 3;
  if (_montoRe.hasMatch(window)) return 2;
  if (_nounRe.hasMatch(window)) return 1;
  return 0;
}

CaptureDirection _direction(String folded, int at) {
  if (_outPaid.hasMatch(folded)) return CaptureDirection.out;
  CaptureDirection? nearest(RegExp out, RegExp inbound) {
    int? distance(RegExp r) {
      int? best;
      for (final m in r.allMatches(folded)) {
        final d = (m.start - at).abs();
        if (best == null || d < best) best = d;
      }
      return best;
    }

    final o = distance(out);
    final i = distance(inbound);
    if (o == null && i == null) return null;
    if (o == null) return CaptureDirection.inbound;
    if (i == null) return CaptureDirection.out;
    return i < o ? CaptureDirection.inbound : CaptureDirection.out;
  }

  return nearest(_outVerbs, _inVerbs) ?? nearest(_outNouns, _inNouns) ?? CaptureDirection.out;
}

String? _cleanParty(String raw) {
  var v = raw.replaceAll(_partyEdges, '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (v.endsWith('.') && !RegExp(r'\.\p{L}\.$', unicode: true).hasMatch(v)) v = v.substring(0, v.length - 1);
  if (v.isEmpty || v.length > 60 || !_hasLetter.hasMatch(v)) return null;
  if (_notAParty.hasMatch(_fold(v))) return null;
  return v;
}

/// Primer valor válido tras una preposición dentro del trozo.
String? _partyIn(String raw, RegExp preposition) {
  final folded = _fold(raw);
  for (final m in preposition.allMatches(folded)) {
    final rest = folded.substring(m.end);
    final cut = _valueEnd.firstMatch(rest);
    final value = raw.substring(m.end, m.end + (cut?.start ?? rest.length));
    final foldedValue = _fold(value);
    final own = m[0]!.trimLeft().startsWith('a') ? _ownAccountPrefix.firstMatch(foldedValue) : null;
    final party = _cleanParty(own == null ? value : value.substring(own.end));
    if (party != null) return party;
  }
  return null;
}

String? _labelledParty(String masked, String folded) {
  for (final m in _counterpartyLabel.allMatches(folded)) {
    final rest = folded.substring(m.end);
    final cut = _fieldEnd.firstMatch(rest);
    final party = _cleanParty(masked.substring(m.end, m.end + (cut?.start ?? rest.length)));
    if (party != null) return party;
  }
  return null;
}

String? _counterparty(String masked, String folded, _Amount a, CaptureDirection direction) {
  final labelled = _labelledParty(masked, folded);
  if (labelled != null) return labelled;
  final start = _sentenceStart(folded, 0, a.start);
  final end = _sentenceEnd(folded, a.end);
  final before = masked.substring(start, a.start);
  final after = masked.substring(a.end, end);
  if (direction == CaptureDirection.inbound) {
    final named = _sentByName.firstMatch(_fold(before));
    if (named != null) {
      final party = _cleanParty(before.substring(named.start, named.start + named[1]!.length));
      if (party != null) return party;
    }
    final de = RegExp(r'\bde\s+');
    return _partyIn(after, de) ?? _partyIn(before, de);
  }
  final to = RegExp(r'\b(?:en|a|para)\s+');
  return _partyIn(after, to) ?? _partyIn(before, to);
}

String? _operationId(String raw, String folded) {
  for (final p in [_idPrimary, _idGeneric, _idOperation, _idExternal]) {
    final m = p.firstMatch(folded);
    if (m != null) return raw.substring(m.end - m[1]!.length, m.end);
  }
  return null;
}

({String? own, String? to}) _digits(String folded, CaptureDirection direction) {
  // CCI, identificadores y teléfonos no son los últimos dígitos de una cuenta.
  final clean = _maskFields(folded, _sensitive.take(6));
  final found = [
    ...[_maskedDigits, _endsInDigits, _plainAccountDigits].expand((p) => p.allMatches(clean)),
  ]..sort((a, b) => a.start.compareTo(b.start));
  String? own;
  String? to;
  for (final m in found) {
    final from = m.start < 30 ? 0 : m.start - 30;
    final ctx = clean.substring(from, m.start);
    if (direction == CaptureDirection.inbound) {
      if (!RegExp(r'\b(?:desde|origen|de la)\b').hasMatch(ctx)) own ??= m[1];
    } else if (RegExp(r'\ba\s+(?:tu\s+|la\s+|mi\s+|su\s+)?(?:cuenta|tarjeta)|destino|hacia|beneficiario').hasMatch(ctx)) {
      to ??= m[1];
    } else {
      own ??= m[1];
    }
  }
  return (own: own, to: to);
}

DateTime? _validDate(int year, int month, int day) {
  final d = DateTime(year, month, day);
  return d.year == year && d.month == month && d.day == day ? d : null;
}

DateTime? _parseDate(String folded, DateTime now) {
  Match? match;
  DateTime? date;
  if (_isoDate.firstMatch(folded) case final m?) {
    match = m;
    date = _validDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  } else if (_dmyDate.firstMatch(folded) case final m?) {
    match = m;
    final y = int.parse(m[3]!);
    date = _validDate(y < 100 ? 2000 + y : y, int.parse(m[2]!), int.parse(m[1]!));
  } else if (_wordDate.firstMatch(folded) case final m?) {
    match = m;
    final names = _months.replaceAll('septiembre|', '').split('|');
    final name = m[2] == 'septiembre' ? 'setiembre' : m[2]!;
    final month = names.indexOf(name) + 1;
    date = _dateNoYear(m[3] == null ? null : int.parse(m[3]!), month, int.parse(m[1]!), now);
  } else if (_dmDate.firstMatch(folded) case final m?) {
    match = m;
    date = _dateNoYear(null, int.parse(m[2]!), int.parse(m[1]!), now);
  }
  if (date == null || match == null) return null;
  if (date.isAfter(now.add(const Duration(days: 1)))) return null;
  if (date.isBefore(now.subtract(const Duration(days: 370)))) return null;

  final time = _timeAfter.firstMatch(folded.substring(match.end));
  if (time == null) return date;
  var hour = int.parse(time[1]!);
  final minute = int.parse(time[2]!);
  if (time[3] == 'p' && hour < 12) hour += 12;
  if (time[3] == 'a' && hour == 12) hour = 0;
  if (hour > 23 || minute > 59) return date;
  return DateTime(date.year, date.month, date.day, hour, minute);
}

DateTime? _dateNoYear(int? year, int month, int day, DateTime now) {
  final d = _validDate(year ?? now.year, month, day);
  if (d == null || year != null || !d.isAfter(now.add(const Duration(days: 1)))) return d;
  return _validDate(now.year - 1, month, day);
}

/// Interpreta un aviso, correo o SMS bancario, solo en el teléfono. null si no
/// reconoce con confianza el importe de una operación: entonces no se crea nada.
ParsedBankText? parseBankText(String text, {required String fallbackCurrency, required DateTime now}) {
  final raw = _plainSpaces(text);
  final masked = _maskFields(raw, _sensitive);
  final folded = _fold(masked);
  final amounts = _findAmounts(folded, fallbackCurrency);

  final chosen = _chooseAmount(folded, amounts, fallbackCurrency);
  if (chosen == null) return null;

  final rawFolded = _fold(raw);
  final direction = _direction(folded, chosen.start);
  final digits = _digits(rawFolded, direction);
  final isTransfer = _lemonPhrase.hasMatch(folded) || (_transferWords.hasMatch(rawFolded) && !_purchaseWords.hasMatch(rawFolded));
  return ParsedBankText(
    amountMinor: chosen.minor,
    currency: chosen.currency ?? fallbackCurrency,
    direction: direction,
    counterparty: _counterparty(masked, folded, chosen, direction),
    date: _parseDate(rawFolded, now),
    operationId: _operationId(raw, rawFolded),
    accountDigits: digits.own,
    toAccountDigits: digits.to,
    isTransfer: isTransfer,
  );
}

_Amount? _chooseAmount(String folded, List<_Amount> amounts, String fallback) {
  // Regla de Lemon/Dale: su frase dice cuál es el importe.
  final lemon = _lemonPhrase.firstMatch(folded);
  if (lemon != null) {
    final a = amounts.where((x) => x.start >= lemon.end - 1).firstOrNull;
    if (a != null) return a;
  }

  // Regla genérica.
  final trimmed = folded.trim();
  if (amounts.isEmpty && _onlyAmount.hasMatch(trimmed)) return _amount(0, 0, trimmed.length, trimmed, null);

  final kept = <(_Amount, String)>[];
  for (var i = 0; i < amounts.length; i++) {
    final window = _beforeWindow(folded, amounts, i);
    if (!_discarded(window, folded.substring(amounts[i].end))) kept.add((amounts[i], window));
  }
  if (kept.isEmpty) return null;

  (_Amount, String)? best;
  var bestRank = 0;
  for (final k in kept) {
    final r = _rank(k.$2);
    if (r > bestRank) {
      best = k;
      bestRank = r;
    }
  }

  if (best != null) {
    final a = best.$1;
    // Un verbo en pasado manda: el pie de un correo no anula el pago. Solo cuenta
    // lo que diga su propia frase.
    final scope = bestRank == 3 ? '${best.$2}${folded.substring(a.start, _sentenceEnd(folded, a.end))}' : folded;
    return _blockers.hasMatch(scope) ? null : a;
  }

  // El texto entero es solo un importe.
  final first = kept.first.$1;
  if (trimmed.length == first.end - first.start) return first;
  if (!_anyOpRe.hasMatch(folded) || _blockers.hasMatch(folded)) return null;
  // Sin nada delante, solo si no hay otro importe con el que confundirlo.
  return {for (final k in kept) k.$1.minor}.length == 1 ? first : null;
}

/// [text] sin lo que pertenece al otro lado de la operación (destinatario, su
/// entidad, CCI, identificadores), para buscar en él el nombre de una cuenta propia.
String accountSearchText(String text, ParsedBankText parsed) {
  var masked = _maskFields(_plainSpaces(text), _sensitive);
  final folded = _fold(masked);
  final chars = masked.split('');
  for (final m in _otherPartyLabel.allMatches(folded)) {
    final rest = folded.substring(m.end);
    final cut = _fieldEnd.firstMatch(rest);
    chars.fillRange(m.start, m.end + (cut?.start ?? rest.length), _mask);
  }
  masked = chars.join();
  final party = parsed.counterparty;
  if (party == null) return masked;
  return masked.replaceAll(RegExp(RegExp.escape(party), caseSensitive: false), _mask);
}
