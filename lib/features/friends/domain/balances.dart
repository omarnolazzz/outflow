import 'shared_expense.dart';

/// Saldo con un amigo por moneda (positivo = te debe; negativo = le debes).
class Balance {
  const Balance({required this.friendUid, required this.byCurrency});

  final String friendUid;
  final Map<String, int> byCurrency;
}

/// Saldos con cada amigo según las deudas no saldadas en las que participa
/// [myUid]. Los amigos con todo a 0 no aparecen.
List<Balance> computeBalances(List<SharedExpense> expenses, String myUid) {
  final totals = <String, Map<String, int>>{};
  void add(String friend, String currency, int minor) {
    final m = totals.putIfAbsent(friend, () => {});
    m[currency] = (m[currency] ?? 0) + minor;
  }

  for (final e in expenses) {
    if (e.paidBy == myUid) {
      for (final d in e.debtors) {
        if (!e.isSettled(d)) add(d, e.currency, e.shareOf(d));
      }
    } else if (e.debtors.contains(myUid) && !e.isSettled(myUid)) {
      add(e.paidBy, e.currency, -e.shareOf(myUid));
    }
  }

  final result = <Balance>[];
  totals.forEach((uid, m) {
    final nonZero = Map.fromEntries(m.entries.where((x) => x.value != 0));
    if (nonZero.isNotEmpty) result.add(Balance(friendUid: uid, byCurrency: nonZero));
  });
  return result;
}

/// Totales de lo que te deben y lo que debes, por moneda.
({Map<String, int> owedToMe, Map<String, int> iOwe}) totalsByCurrency(List<Balance> balances) {
  final owed = <String, int>{};
  final owe = <String, int>{};
  for (final b in balances) {
    b.byCurrency.forEach((c, v) {
      if (v > 0) owed[c] = (owed[c] ?? 0) + v;
      if (v < 0) owe[c] = (owe[c] ?? 0) - v;
    });
  }
  return (owedToMe: owed, iOwe: owe);
}
