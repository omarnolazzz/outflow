import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import '../../../core/domain/money.dart';
import '../../wallet/domain/category.dart';
import '../../wallet/domain/default_categories.dart';
import '../../wallet/domain/expense_hints.dart';
import '../../wallet/domain/movement.dart';
import '../../wallet/domain/wallet_account.dart';
import 'parse_bank_text.dart';

/// Nota del movimiento creado ante la duda de si ya estaba apuntado.
const kDuplicateNote = '¿duplicado?';

/// Un texto bancario recibido por cualquier vía. Su texto no sale del teléfono.
@immutable
class CaptureEvent {
  const CaptureEvent({
    required this.sourceKey,
    required this.sourceLabel,
    required this.text,
    required this.receivedAt,
    this.imageOperationId,
  });

  /// Paquete de Android o remitente, para saber a qué cuenta pertenece.
  final String sourceKey;
  final String sourceLabel;
  final String text;
  final DateTime receivedAt;

  /// Número de operación leído de una imagen adjunta.
  final String? imageOperationId;

  Map<String, Object?> toJson() => {
        'sourceKey': sourceKey,
        'sourceLabel': sourceLabel,
        'text': text,
        'receivedAt': receivedAt.toIso8601String(),
        'imageOperationId': imageOperationId,
      };

  factory CaptureEvent.fromJson(Map<String, Object?> json) => CaptureEvent(
        sourceKey: json['sourceKey'] as String,
        sourceLabel: json['sourceLabel'] as String? ?? json['sourceKey'] as String,
        text: json['text'] as String,
        receivedAt: DateTime.parse(json['receivedAt'] as String),
        imageOperationId: json['imageOperationId'] as String?,
      );
}

/// Lo que hay que guardar tras procesar una tanda de eventos.
@immutable
class CaptureOutcome {
  const CaptureOutcome({required this.upsert, required this.unmatchedSources});

  final List<Movement> upsert;

  /// Eventos que acabaron en la cuenta por defecto porque nada indicaba otra.
  final List<CaptureEvent> unmatchedSources;
}

/// Id derivado del evento: procesarlo dos veces no puede crear dos movimientos.
String captureMovementId(CaptureEvent e) {
  final key = '${e.sourceKey}|${e.receivedAt.toUtc().toIso8601String()}|${e.text}';
  return 'capture:${sha256.convert(utf8.encode(key)).toString().substring(0, 32)}';
}

const _windowDays = 2;

/// Nombres que aparecen en cualquier texto bancario sin referirse a esa cuenta.
const _genericAccountNames = {'mi cuenta', 'cuenta', 'tarjeta', 'efectivo'};

bool _digitsMatch(String? own, String digits) {
  if (own == null || own.length < 3) return false;
  return own.endsWith(digits) || digits.endsWith(own);
}

/// La única cuenta cuyos últimos dígitos coinciden con [digits].
WalletAccount? accountByDigits(List<WalletAccount> active, String? digits) {
  if (digits == null) return null;
  final found = active.where((a) => _digitsMatch(a.lastDigits, digits)).toList();
  return found.length == 1 ? found.first : null;
}

/// La cuenta nombrada como tuya en [text] ("tu cuenta X", "tarjeta X"); con dos o
/// más, ninguna. Un nombre suelto no cuenta: "en BCP" puede ser el banco de otro y
/// "Dale clic" no es la cuenta Dale.
WalletAccount? _byOwnName(List<WalletAccount> active, String text) {
  final haystack = normalizeMerchant(text);
  final found = <WalletAccount>[];
  for (final a in active) {
    final name = normalizeMerchant(a.name);
    if (name.length < 3 || _genericAccountNames.contains(name)) continue;
    final own = RegExp(
      '(?<![\\p{L}\\p{N}])(?:cuenta|tarjeta)\\s+(?:de\\s+)?(?:credito\\s+|debito\\s+)?${RegExp.escape(name)}(?![\\p{L}\\p{N}])',
      unicode: true,
    );
    if (own.hasMatch(haystack)) found.add(a);
  }
  return found.length == 1 ? found.first : null;
}

/// La cuenta que se llama exactamente [party]: el otro lado de una transferencia.
WalletAccount? _byExactName(List<WalletAccount> active, String party) {
  final name = normalizeMerchant(party);
  if (_genericAccountNames.contains(name)) return null;
  final found = active.where((a) => normalizeMerchant(a.name) == name).toList();
  return found.length == 1 ? found.first : null;
}

/// Cómo afecta un movimiento a una cuenta, para comparar con un evento.
({CaptureDirection direction, int minor, String? currency})? accountSide(Movement m, String accountId, String defaultAccountId) {
  if (m.origin == MovementOrigin.subscription) return null;
  final mine = (m.accountId ?? defaultAccountId) == accountId;
  switch (m.kind) {
    case MovementKind.adjustment:
      return null;
    case MovementKind.expense:
      return mine ? (direction: CaptureDirection.out, minor: m.paidMinor ?? m.amount.minor, currency: m.amount.currency) : null;
    case MovementKind.income:
      return mine ? (direction: CaptureDirection.inbound, minor: m.amount.minor, currency: m.amount.currency) : null;
    case MovementKind.transfer:
      if (m.toAccountId == accountId) {
        return (direction: CaptureDirection.inbound, minor: m.receivedMinor ?? m.amount.minor, currency: m.receivedMinor == null ? m.amount.currency : null);
      }
      if (!mine) return null;
      return m.toAccountId == null && m.transferIncoming
          ? (direction: CaptureDirection.inbound, minor: m.receivedMinor ?? m.amount.minor, currency: m.receivedMinor == null ? m.amount.currency : null)
          : (direction: CaptureDirection.out, minor: m.amount.minor, currency: m.amount.currency);
  }
}

/// Mismo comercio, uno dentro del otro por palabras enteras, o alguno vacío.
bool _compatibleMerchants(String a, String b) {
  final x = normalizeMerchant(a);
  final y = normalizeMerchant(b);
  if (x.isEmpty || y.isEmpty || x == y) return true;
  return ' $x '.contains(' $y ') || ' $y '.contains(' $x ');
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

int _calendarDaysApart(DateTime a, DateTime b) =>
    DateTime.utc(a.year, a.month, a.day).difference(DateTime.utc(b.year, b.month, b.day)).inDays.abs();

/// ¿Puede [m] ser otro rastro de una operación en la cuenta [accountId]? Las reglas
/// que comparten la captura y la importación: misma cuenta, sentido e importe, misma
/// moneda, fecha cercana y sin dos referencias distintas (son dos operaciones).
///
/// La fecha se compara con [window] o, con [calendarDays], por días de calendario
/// (un estado de cuenta solo trae el día). Con [merchant] también se exige un
/// comercio compatible: la descripción de un banco no se parece al de un aviso, así
/// que la importación no lo pasa.
bool isDuplicate(
  Movement m, {
  required String accountId,
  required String defaultAccountId,
  required CaptureDirection direction,
  required int amountMinor,
  required String currency,
  required DateTime date,
  Duration window = const Duration(days: _windowDays),
  int? calendarDays,
  String? merchant,
  String? ref,
}) {
  final side = accountSide(m, accountId, defaultAccountId);
  if (side == null || side.direction != direction || side.minor != amountMinor) return false;
  if (side.currency != null && side.currency != currency) return false;
  if (calendarDays != null) {
    if (_calendarDaysApart(m.date, date) > calendarDays) return false;
  } else if (m.date.difference(date).abs() > window) {
    return false;
  }
  if (merchant != null && !_compatibleMerchants(m.title, merchant)) return false;
  if (ref != null && m.externalRef != null && m.externalRef!.toLowerCase() != ref.toLowerCase()) return false;
  return true;
}

String _fallbackCategory(List<Category> categories, MovementKind kind, {String? preferred}) {
  final ofKind = categories.where((c) => c.kind == kind && !c.reserved).toList();
  final ids = {for (final c in ofKind) c.id};
  for (final id in [?preferred, if (kind == MovementKind.expense) 'expense_other' else kOtherIncomeCategoryId]) {
    if (ids.contains(id)) return id;
  }
  return ofKind.firstOrNull?.id ?? kNoCategoryId;
}

/// Convierte los eventos en movimientos por revisar, sin efectos: quien llama
/// guarda [CaptureOutcome.upsert]. Los duplicados solo se buscan dentro de la
/// misma cuenta; ante la duda se crea con la nota [kDuplicateNote], porque
/// perder un movimiento en silencio cambia los números sin que se note.
CaptureOutcome processCaptures({
  required List<CaptureEvent> events,
  required List<WalletAccount> accounts,
  required List<Movement> movements,
  required Map<String, String> sourceAccounts,
  required List<Category> categories,
  required String defaultAccountId,
  required DateTime now,
}) {
  final active = accounts.where((a) => !a.archived).toList();
  final defaultAccount = accounts.where((a) => a.id == defaultAccountId).firstOrNull;
  if (defaultAccount == null) return const CaptureOutcome(upsert: [], unmatchedSources: []);

  final working = [...movements];
  final upsert = <String, Movement>{};
  final unmatched = <CaptureEvent>[];

  void put(Movement m) {
    final i = working.indexWhere((x) => x.id == m.id);
    if (i == -1) {
      working.add(m);
    } else {
      working[i] = m;
    }
    upsert[m.id] = m;
  }

  for (final event in events) {
    final id = captureMovementId(event);
    // Ya procesado (corte entre guardar y vaciar la bandeja), creado o fundido.
    if (working.any((m) => m.id == id || m.pairedCaptureId == id)) continue;

    final first = parseBankText(event.text, fallbackCurrency: defaultAccount.currency, now: now);
    if (first == null) continue;

    final source = active.where((a) => a.id == sourceAccounts[event.sourceKey]).firstOrNull;
    final account = accountByDigits(active, first.accountDigits) ?? _byOwnName(active, accountSearchText(event.text, first)) ?? source;
    if (account == null) unmatched.add(event);
    final own = account ?? defaultAccount;

    // Un importe sin moneda está en la de su cuenta.
    final parsed = parseBankText(event.text, fallbackCurrency: own.currency, now: now) ?? first;
    final ref = parsed.operationId ?? event.imageOperationId;
    final merchant = parsed.counterparty ?? '';
    final date = parsed.date == null || _sameDay(parsed.date!, event.receivedAt) ? event.receivedAt : parsed.date!;

    // La misma referencia en la misma cuenta siempre es la misma operación.
    if (ref != null) {
      final same = working
          .where((m) => m.externalRef?.toLowerCase() == ref.toLowerCase() && accountSide(m, own.id, defaultAccountId) != null)
          .firstOrNull;
      if (same != null) {
        if (same.title.isEmpty && merchant.isNotEmpty) put(same.copyWith(title: merchant));
        continue;
      }
    }

    final candidates = <Movement>[];
    for (final m in working) {
      if (isDuplicate(
        m,
        accountId: own.id,
        defaultAccountId: defaultAccountId,
        direction: parsed.direction,
        amountMinor: parsed.amountMinor,
        currency: parsed.currency,
        date: date,
        merchant: merchant,
        ref: ref,
      )) {
        candidates.add(m);
      }
    }
    candidates.sort((a, b) => a.date.difference(date).abs().compareTo(b.date.difference(date).abs()));

    // Una referencia y un aviso sin ella son dos rastros del mismo pago, pero cada
    // movimiento solo absorbe uno: otro aviso igual es dinero nuevo. Dos sin
    // referencia pueden ser dos pagos reales: eso es duda, no duplicado.
    final pairable = candidates.where((m) {
      if (m.pairedCaptureId != null) return false;
      if (ref == null && m.externalRef == null) return false;
      return _sameDay(m.date, date) || (m.title.isNotEmpty && merchant.isNotEmpty);
    }).firstOrNull;
    if (pairable != null) {
      put(pairable.copyWith(
        title: pairable.title.isEmpty && merchant.isNotEmpty ? merchant : null,
        externalRef: ref,
        pairedCaptureId: id,
      ));
      continue;
    }

    final note = candidates.isEmpty ? '' : kDuplicateNote;
    final transfer = _ownTransfer(parsed, own, active);
    if (transfer != null) {
      put(Movement(
        id: id,
        kind: MovementKind.transfer,
        amount: Money(parsed.amountMinor, parsed.currency),
        categoryId: kNoCategoryId,
        date: date,
        createdAt: now,
        title: '${transfer.from.name} → ${transfer.to.name}',
        note: note,
        origin: MovementOrigin.capture,
        accountId: transfer.from.id,
        toAccountId: transfer.to.id,
        needsReview: true,
        externalRef: ref,
      ));
      continue;
    }

    final isOut = parsed.direction == CaptureDirection.out;
    put(Movement(
      id: id,
      kind: isOut ? MovementKind.expense : MovementKind.income,
      amount: Money(parsed.amountMinor, parsed.currency),
      categoryId: isOut
          ? suggestCategory(merchant: merchant, history: working, categories: categories) ?? _fallbackCategory(categories, MovementKind.expense)
          : _fallbackCategory(categories, MovementKind.income, preferred: parsed.isTransfer ? 'transfer_in' : null),
      date: date,
      createdAt: now,
      title: merchant,
      note: note,
      origin: MovementOrigin.capture,
      accountId: own.id,
      needsReview: true,
      externalRef: ref,
    ));
  }

  return CaptureOutcome(upsert: upsert.values.toList(), unmatchedSources: unmatched);
}

/// Las dos cuentas de una transferencia, solo si el otro lado es una cuenta propia
/// reconocida y distinta, en la misma moneda (lo recibido en otra no se adivina).
({WalletAccount from, WalletAccount to})? _ownTransfer(ParsedBankText p, WalletAccount own, List<WalletAccount> active) {
  if (!p.isTransfer) return null;
  final party = p.counterparty;
  final other = accountByDigits(active, p.toAccountDigits) ?? (party == null ? null : _byExactName(active, party));
  if (other == null || other.id == own.id) return null;
  if (own.currency != p.currency || other.currency != p.currency) return null;
  return p.direction == CaptureDirection.out ? (from: own, to: other) : (from: other, to: own);
}

/// El usuario dice que este gasto o ingreso era dinero entre sus cuentas: [own]
/// es la del movimiento y [other] la del otro lado. Queda revisado.
Movement convertToTransfer(Movement m, {required WalletAccount own, required WalletAccount other}) {
  final from = m.kind == MovementKind.income ? other : own;
  final to = m.kind == MovementKind.income ? own : other;
  return m.copyWith(
    kind: MovementKind.transfer,
    categoryId: kNoCategoryId,
    title: '${from.name} → ${to.name}',
    accountId: from.id,
    toAccountId: to.id,
    needsReview: false,
  );
}
