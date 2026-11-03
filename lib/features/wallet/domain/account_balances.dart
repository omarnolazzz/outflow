import 'package:uuid/uuid.dart';

import '../../../core/domain/money.dart';
import 'movement.dart';
import 'wallet_account.dart';

/// Cuánto cambia [m] el saldo de la cuenta [accountId], en unidades menores.
/// Un movimiento sin cuenta es de [defaultAccountId]. No mira monedas: de eso
/// se encarga [computeBalances].
int accountEffectMinor(Movement m, String accountId, String defaultAccountId) {
  // El cobro de una suscripción es informativo: se paga aparte.
  if (m.origin == MovementOrigin.subscription) return 0;
  final mine = (m.accountId ?? defaultAccountId) == accountId;
  switch (m.kind) {
    case MovementKind.income:
      return mine ? m.amount.minor : 0;
    case MovementKind.expense:
      return mine ? -(m.paidMinor ?? m.amount.minor) : 0;
    case MovementKind.adjustment:
      return mine ? m.adjustmentMinor ?? 0 : 0;
    case MovementKind.transfer:
      final received = m.receivedMinor ?? m.amount.minor;
      // Con el otro lado desconocido, solo se mueve su cuenta.
      if (m.toAccountId == null) {
        if (!mine) return 0;
        return m.transferIncoming ? received : -m.amount.minor;
      }
      return (m.toAccountId == accountId ? received : 0) - (mine ? m.amount.minor : 0);
  }
}

/// Una cuenta solo cuenta movimientos en su moneda. El destino de una
/// transferencia está exento: lo que recibe ya está en la suya. Si se desconoce
/// el otro lado, solo cuando se indicó lo recibido: sin ese dato, el importe en
/// otra moneda no se puede sumar.
bool _countsIn(Movement m, WalletAccount account, String defaultAccountId) {
  if (m.amount.currency == account.currency) return true;
  if (m.kind != MovementKind.transfer) return false;
  if (m.toAccountId != null) return m.toAccountId == account.id;
  return m.transferIncoming && m.receivedMinor != null && (m.accountId ?? defaultAccountId) == account.id;
}

/// Saldo de cada cuenta, también de las archivadas: saldo inicial más el efecto
/// de sus movimientos.
Map<String, int> computeBalances(List<WalletAccount> accounts, List<Movement> movements) {
  final defaultId = defaultAccountOf(accounts)?.id;
  if (defaultId == null) return {};
  return {
    for (final a in accounts)
      a.id: movements.fold<int>(
        a.initialMinor,
        (sum, m) => _countsIn(m, a, defaultId) ? sum + accountEffectMinor(m, a.id, defaultId) : sum,
      ),
  };
}

/// Total por moneda de las cuentas sin archivar, sin convertir.
Map<String, int> totalsByCurrency(List<WalletAccount> accounts, Map<String, int> balances) {
  final totals = <String, int>{};
  for (final a in accounts) {
    if (a.archived) continue;
    totals.update(a.currency, (v) => v + (balances[a.id] ?? 0), ifAbsent: () => balances[a.id] ?? 0);
  }
  return totals;
}

/// Movimiento que lleva el saldo de [account] de [currentMinor] a [realMinor];
/// null si no hay diferencia.
Movement? makeAdjustment({
  required WalletAccount account,
  required int currentMinor,
  required int realMinor,
  required DateTime now,
}) {
  final difference = realMinor - currentMinor;
  if (difference == 0) return null;
  return Movement(
    id: const Uuid().v4(),
    kind: MovementKind.adjustment,
    amount: Money(difference.abs(), account.currency),
    categoryId: kNoCategoryId,
    date: now,
    createdAt: now,
    title: 'Ajuste de saldo',
    accountId: account.id,
    adjustmentMinor: difference,
  );
}

/// Transferencia de [amountMinor] (en la moneda de [from]) a otra cuenta propia.
/// Entre monedas distintas hay que indicar [receivedMinor], en la de [to].
Movement makeTransfer({
  required WalletAccount from,
  required WalletAccount to,
  required int amountMinor,
  int? receivedMinor,
  required DateTime date,
  String note = '',
}) {
  if (from.id == to.id) throw ArgumentError('Una transferencia necesita dos cuentas distintas.');
  if (from.currency != to.currency && receivedMinor == null) {
    throw ArgumentError('Entre monedas distintas hay que indicar el importe recibido.');
  }
  return Movement(
    id: const Uuid().v4(),
    kind: MovementKind.transfer,
    amount: Money(amountMinor, from.currency),
    categoryId: kNoCategoryId,
    date: date,
    createdAt: date,
    title: '${from.name} → ${to.name}',
    note: note,
    accountId: from.id,
    toAccountId: to.id,
    receivedMinor: receivedMinor,
  );
}
