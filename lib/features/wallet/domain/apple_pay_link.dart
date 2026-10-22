import 'package:meta/meta.dart';

import 'movement.dart';

/// Gasto a medio rellenar que abre la hoja (atajo de Apple Pay, ticket…).
@immutable
class MovementDraft {
  const MovementDraft({
    this.amountMinor,
    this.currency,
    this.title = '',
    this.categoryId,
    this.date,
    this.origin = MovementOrigin.manual,
    this.note = '',
  });

  final int? amountMinor;
  final String? currency;
  final String title;
  final String? categoryId;
  final DateTime? date;
  final MovementOrigin origin;
  final String note;

  MovementDraft copyWith({String? categoryId}) => MovementDraft(
        amountMinor: amountMinor,
        currency: currency,
        title: title,
        categoryId: categoryId ?? this.categoryId,
        date: date,
        origin: origin,
        note: note,
      );
}

/// Símbolos y códigos que pueden acompañar al importe, del más largo al más
/// corto para que "US$" gane a "$".
const _currencyTokens = <String, String>{
  'US\$': 'USD',
  'MX\$': 'MXN',
  'COL\$': 'COP',
  'AR\$': 'ARS',
  'CLP\$': 'CLP',
  'R\$': 'BRL',
  'S/': 'PEN',
  'PEN': 'PEN',
  'USD': 'USD',
  'EUR': 'EUR',
  'MXN': 'MXN',
  'COP': 'COP',
  'ARS': 'ARS',
  'CLP': 'CLP',
  'GBP': 'GBP',
  'BRL': 'BRL',
  '€': 'EUR',
  '£': 'GBP',
  '\$': 'USD',
};

/// `outflow://gasto?importe=…&comercio=…&tarjeta=…` (automatización
/// "Transacción" de Atajos) → borrador de gasto. null si es otro enlace.
MovementDraft? parseApplePayLink(Uri uri, {required String fallbackCurrency, required DateTime now}) {
  if (uri.scheme != 'outflow' || uri.host != 'gasto') return null;
  final raw = (uri.queryParameters['importe'] ?? '').trim();
  final card = (uri.queryParameters['tarjeta'] ?? '').trim();

  String? currency;
  for (final e in _currencyTokens.entries) {
    if (raw.toUpperCase().contains(e.key)) {
      currency = e.value;
      break;
    }
  }

  return MovementDraft(
    amountMinor: parseAmountMinor(raw),
    currency: currency ?? fallbackCurrency,
    title: (uri.queryParameters['comercio'] ?? '').trim(),
    date: now,
    origin: MovementOrigin.applePay,
    note: card.isEmpty ? '' : 'Tarjeta: $card',
  );
}

/// Importe en unidades menores a partir de un texto con separadores de miles
/// y decimales en cualquier convención ("1.234,56", "1,234.56", "12,5").
int? parseAmountMinor(String text) {
  final s = text.replaceAll(RegExp(r'[^0-9.,]'), '');
  if (!RegExp(r'\d').hasMatch(s)) return null;

  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');
  int? decimalAt;
  if (lastDot >= 0 && lastComma >= 0) {
    decimalAt = lastDot > lastComma ? lastDot : lastComma;
  } else {
    final sep = lastDot >= 0 ? '.' : (lastComma >= 0 ? ',' : null);
    if (sep != null) {
      final count = sep.allMatches(s).length;
      final after = s.length - s.lastIndexOf(sep) - 1;
      // Un único separador seguido de 1–2 cifras es decimal; con 3 son miles.
      if (count == 1 && after > 0 && after <= 2) decimalAt = s.lastIndexOf(sep);
    }
  }

  final whole = (decimalAt == null ? s : s.substring(0, decimalAt)).replaceAll(RegExp(r'[.,]'), '');
  final frac = decimalAt == null ? '' : s.substring(decimalAt + 1).replaceAll(RegExp(r'[.,]'), '');
  final cents = int.parse(frac.padRight(2, '0').substring(0, 2));
  return (int.tryParse(whole.isEmpty ? '0' : whole) ?? 0) * 100 + cents;
}
