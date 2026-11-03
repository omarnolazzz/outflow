import '../../capture/domain/parse_bank_text.dart' show labelledOperationId;
import '../../wallet/domain/apple_pay_link.dart' show parseAmountMinor;
import 'receipt.dart';

const _months = {
  'ENERO': 1, 'FEBRERO': 2, 'MARZO': 3, 'ABRIL': 4, 'MAYO': 5, 'JUNIO': 6, 'JULIO': 7,
  'AGOSTO': 8, 'SEPTIEMBRE': 9, 'SETIEMBRE': 9, 'OCTUBRE': 10, 'NOVIEMBRE': 11, 'DICIEMBRE': 12,
};

/// Palabras de líneas que no son productos (totales, impuestos, pago).
const _notItem = ['TOTAL', 'IGV', 'IVA', 'BASE', 'OP.', 'GRAVADA', 'EFECTIVO', 'VUELTO', 'CAMBIO', 'TARJETA', 'DESCUENTO'];

/// Prefijos de líneas que no son el nombre del comercio.
const _notMerchant = ['RUC', 'CIF', 'NIF', 'AV.', 'AV ', 'CALLE', 'JR.', 'JR ', 'FECHA', 'BOLETA', 'FACTURA', 'TICKET', 'MESA', 'WWW'];

/// Líneas con TOTAL que no son el total pagado.
const _notTotal = ['SUBTOTAL', 'ART', 'ITEM', 'IVA', 'IGV', 'DESC', 'CUOTA', 'BASE'];

/// Importe con dos decimales ("23,45", "1.234,56").
final _decimalAmount = RegExp(r'\d{1,3}(?:[.,]\d{3})*[.,]\d{2}\b');
final _itemLine = RegExp(r'^(\d{1,3})\s+(.+?)\s+(\d+[.,]\d{2})\s*(?:EUR|PEN|USD|S/|€|\$)?$');

/// Constancia de una transferencia (Plin, Yape…): la pantalla que deja el pago.
final _constanciaWord = RegExp(r'\bCONSTANCIA\b');
final _transferWords = RegExp(r'\b(?:PLIN|YAPE|YAPEASTE|PLINEASTE|TRANSFERENCIA|ENV[IÍ]O|OPERACI[OÓ]N EXITOSA)\b');
final _recipientLine = RegExp(r'^(?:PARA|DESTINO|DESTINATARIO|NOMBRE)(?:\s*:\s*|\s+)(.+)$|^A\s*:\s*(.+)$', caseSensitive: false);
final _prefixedAmount = RegExp(r'(?:S/\.?|US\$|\$|€)\s*(\d[\d.,]*)');

/// Lectura local, sin red, de un ticket: el total de la línea TOTAL (no el
/// subtotal ni el vuelto), la fecha más plausible, el comercio y los productos.
ReceiptData parseReceiptHeuristic(String text, {required DateTime now, required String fallbackCurrency}) {
  final lines = [
    for (final l in text.split('\n'))
      if (l.trim().isNotEmpty) l.trim().replaceAll(RegExp(r'\s+'), ' '),
  ];
  final upper = text.toUpperCase();

  // Solo marcas explícitas: "S/N" (sin número) o "PENDIENTE" no son soles.
  final currency = RegExp(r'S/\.?\s*\d|\bPEN\b').hasMatch(upper)
      ? 'PEN'
      : RegExp(r'\bEUR\b|€').hasMatch(upper)
          ? 'EUR'
          : RegExp(r'\bUSD\b|US\$').hasMatch(upper)
              ? 'USD'
              : fallbackCurrency;

  // El total es la primera línea TOTAL con un importe con decimales que no sea
  // subtotal, contador de artículos ni desglose de impuestos; "TOTAL A PAGAR"
  // e "IMPORTE TOTAL" tienen prioridad.
  int? total;
  var totalLine = lines.length;
  var totalRank = 0;
  for (final (i, l) in lines.indexed) {
    final u = l.toUpperCase();
    if (!RegExp(r'\bTOTAL\b').hasMatch(u) || _notTotal.any(u.contains)) continue;
    final amount = _decimalAmount.firstMatch(u.replaceAll(RegExp(r'\d+\s*%'), ''));
    if (amount == null) continue;
    final rank = u.contains('A PAGAR') || u.contains('IMPORTE TOTAL') ? 2 : 1;
    if (rank <= totalRank) continue;
    total = parseAmountMinor(amount.group(0)!);
    totalLine = i;
    totalRank = rank;
  }

  // Una constancia no tiene línea TOTAL: el importe es el que lleva moneda, y
  // quien cobra es el destinatario, no la primera línea de texto.
  String? recipient;
  for (final l in lines) {
    final m = _recipientLine.firstMatch(l);
    final name = (m?.group(1) ?? m?.group(2))?.trim();
    if (name != null && RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ]{2}').hasMatch(name)) {
      recipient = name;
      break;
    }
  }
  // Es constancia con la palabra "Constancia", o con un número de operación
  // etiquetado junto a una palabra de transferencia o a un destinatario. Un "Pago:
  // Yape" suelto en un ticket no basta.
  final operationId = labelledOperationId(text);
  final isConstancia = _constanciaWord.hasMatch(upper) ||
      (operationId != null && (_transferWords.hasMatch(upper) || recipient != null));
  if (isConstancia && total == null) {
    final labelled = lines.where((l) => RegExp(r'\b(?:MONTO|IMPORTE)\b').hasMatch(l.toUpperCase()));
    for (final l in [...labelled, ...lines]) {
      final m = _prefixedAmount.firstMatch(l.toUpperCase());
      final amount = m == null ? null : parseAmountMinor(m.group(1)!);
      if (amount != null && amount > 0) {
        total = amount;
        break;
      }
    }
  }

  String? merchant;
  var merchantLine = -1;
  for (final (i, l) in lines.indexed) {
    if (isConstancia) break;
    final u = l.toUpperCase();
    final letters = RegExp(r'[A-ZÁÉÍÓÚÑÜ]').allMatches(u).length;
    final digits = RegExp(r'\d').allMatches(u).length;
    if (letters < 3 || digits > letters / 3) continue;
    if (_notMerchant.any(u.startsWith)) continue;
    merchant = l;
    merchantLine = i;
    break;
  }

  final items = <ReceiptItem>[];
  for (var i = merchantLine + 1; i < totalLine && i < lines.length; i++) {
    final u = lines[i].toUpperCase();
    if (_notItem.any(u.contains)) continue;
    final m = _itemLine.firstMatch(lines[i]);
    if (m == null) continue;
    final amount = parseAmountMinor(m.group(3)!);
    if (amount == null) continue;
    items.add(ReceiptItem(name: m.group(2)!.trim(), quantity: int.parse(m.group(1)!), amountMinor: amount));
  }

  return ReceiptData(
    merchant: isConstancia ? recipient : merchant,
    date: _findDate(lines, now),
    totalMinor: total,
    currency: currency,
    items: items,
    // Solo las constancias: el "N°" de un ticket no identifica ninguna operación.
    operationId: isConstancia ? operationId : null,
    isConstancia: isConstancia,
  );
}

DateTime? _findDate(List<String> lines, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  DateTime? valid(int y, int m, int d) {
    if (y < 100) y += 2000;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final date = DateTime(y, m, d);
    if (date.month != m || date.isAfter(today)) return null;
    return date;
  }

  for (final l in lines) {
    final u = l.toUpperCase();
    final iso = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').firstMatch(u);
    if (iso != null) {
      final d = valid(int.parse(iso[1]!), int.parse(iso[2]!), int.parse(iso[3]!));
      if (d != null) return d;
    }
    final dmy = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b').firstMatch(u);
    if (dmy != null) {
      final d = valid(int.parse(dmy[3]!), int.parse(dmy[2]!), int.parse(dmy[1]!));
      if (d != null) return d;
    }
    final words = RegExp(r'\b(\d{1,2})\s+(?:DE\s+)?([A-ZÁÉÍÓÚ]+)\s+(?:DE\s+)?(\d{4})\b').firstMatch(u);
    final month = words == null ? null : _months[words[2]];
    if (words != null && month != null) {
      final d = valid(int.parse(words[3]!), month, int.parse(words[1]!));
      if (d != null) return d;
    }
  }
  return null;
}
