import 'expense_hints.dart';
import 'movement.dart';

/// Gastos ya registrados que podrían ser el mismo pago que un ticket (o un
/// gasto a dividir): de los últimos [window] alrededor de [date], con importe
/// a menos del 1 % o el mismo comercio. Los más cercanos en el tiempo, primero.
List<Movement> findMatchingPayments({
  required List<Movement> movements,
  required int amountMinor,
  required String? merchant,
  required DateTime date,
  Duration window = const Duration(days: 3),
}) {
  final m = merchant == null ? '' : normalizeMerchant(merchant);
  final tolerance = (amountMinor * 0.01).ceil();
  final out = [
    for (final x in movements)
      if (x.isExpense &&
          x.origin != MovementOrigin.subscription &&
          x.date.difference(date).abs() <= window &&
          ((x.amount.minor - amountMinor).abs() <= tolerance ||
              (m.isNotEmpty && normalizeMerchant(x.title) == m)))
        x,
  ]..sort((a, b) => a.date.difference(date).abs().compareTo(b.date.difference(date).abs()));
  return out;
}
