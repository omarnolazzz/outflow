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

/// Los ajustes de una cuenta como puntos de control: al ajustar, el usuario dijo
/// su saldo real, y ese saldo ya incluía lo ocurrido hasta entonces.
class _Checkpoints {
  _Checkpoints(Iterable<Movement> adjustments) : _adjustments = adjustments.toList() {
    _adjustments.sort((a, b) => a.date.compareTo(b.date));
    _earliestCreated = List.of(_adjustments.map((a) => a.createdAt));
    for (var i = _earliestCreated.length - 2; i >= 0; i--) {
      if (_earliestCreated[i + 1].isBefore(_earliestCreated[i])) _earliestCreated[i] = _earliestCreated[i + 1];
    }
  }

  /// Por fecha, de antes a después.
  final List<Movement> _adjustments;

  /// [i]: el `createdAt` más antiguo entre los ajustes de [i] en adelante.
  late final List<DateTime> _earliestCreated;

  /// [m] se apuntó después de un ajuste con fecha posterior a la suya: ocurrió
  /// antes de ese saldo real y se registró cuando ya estaba incluido.
  bool covers(Movement m) {
    var low = 0;
    var high = _adjustments.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_adjustments[mid].date.isAfter(m.date)) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low < _adjustments.length && m.createdAt.isAfter(_earliestCreated[low]);
  }
}

/// Saldo de cada cuenta, también de las archivadas. `initialMinor` es el saldo en
/// `initialDate`, así que se le suma el efecto de los movimientos desde ese
/// instante (cada cuenta mira el suyo: una transferencia puede contar solo en un
/// lado), salvo los que ya incluía un ajuste ([_Checkpoints]). Los ajustes no los
/// frena otro ajuste.
Map<String, int> computeBalances(List<WalletAccount> accounts, List<Movement> movements) {
  final defaultId = defaultAccountOf(accounts)?.id;
  if (defaultId == null) return {};
  final adjustments = movements.where((m) => m.kind == MovementKind.adjustment).toList();
  final balances = <String, int>{};
  for (final a in accounts) {
    final checkpoints = _Checkpoints(
      adjustments.where((m) => (m.accountId ?? defaultId) == a.id && _countsIn(m, a, defaultId)),
    );
    var balance = a.initialMinor;
    for (final m in movements) {
      if (!_countsIn(m, a, defaultId) || m.date.isBefore(a.initialDate)) continue;
      if (m.kind != MovementKind.adjustment && checkpoints.covers(m)) continue;
      balance += accountEffectMinor(m, a.id, defaultId);
    }
    balances[a.id] = balance;
  }
  return balances;
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
  if (amountMinor <= 0) throw ArgumentError('El importe de una transferencia tiene que ser positivo.');
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
    // Cuándo se apuntó, no cuándo ocurrió: lo necesitan los puntos de control.
    createdAt: DateTime.now(),
    title: '${from.name} → ${to.name}',
    note: note,
    accountId: from.id,
    toAccountId: to.id,
    receivedMinor: receivedMinor,
  );
}
