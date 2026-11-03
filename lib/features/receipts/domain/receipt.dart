import 'package:meta/meta.dart';

@immutable
class ReceiptItem {
  const ReceiptItem({required this.name, this.quantity = 1, required this.amountMinor});

  final String name;
  final int quantity;

  /// Importe de la línea (no el unitario).
  final int amountMinor;

  ReceiptItem copyWith({String? name, int? amountMinor}) =>
      ReceiptItem(name: name ?? this.name, quantity: quantity, amountMinor: amountMinor ?? this.amountMinor);

  @override
  bool operator ==(Object other) =>
      other is ReceiptItem && other.name == name && other.quantity == quantity && other.amountMinor == amountMinor;

  @override
  int get hashCode => Object.hash(name, quantity, amountMinor);
}

/// Lo leído de un ticket. Cualquier campo puede faltar.
@immutable
class ReceiptData {
  const ReceiptData({
    this.merchant,
    this.date,
    this.totalMinor,
    this.currency,
    this.items = const [],
    this.fromAi = false,
    this.operationId,
  });

  final String? merchant;
  final DateTime? date;
  final int? totalMinor;
  final String? currency;
  final List<ReceiptItem> items;

  /// Lo completó la IA (si no, solo la lectura local).
  final bool fromAi;

  /// Número de operación de una constancia (Plin, Yape, transferencia). Los tickets no lo tienen.
  final String? operationId;

  /// Rellena lo que falte con [fallback].
  ReceiptData merge(ReceiptData fallback) => ReceiptData(
        merchant: (merchant?.trim().isNotEmpty ?? false) ? merchant : fallback.merchant,
        date: date ?? fallback.date,
        totalMinor: totalMinor ?? fallback.totalMinor,
        currency: currency ?? fallback.currency,
        items: items.isNotEmpty ? items : fallback.items,
        fromAi: fromAi,
        operationId: operationId ?? fallback.operationId,
      );
}
