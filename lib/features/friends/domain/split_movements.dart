import '../../../core/domain/money.dart';
import '../../../core/utils/formatters.dart';
import '../../wallet/domain/movement.dart';
import '../../wallet/domain/payment_match.dart';
import 'shared_expense.dart';

/// Gastos compartidos tal como llegan del servidor.
///
/// [fromCache] es true cuando aún no se oyó al servidor (offline o recién
/// abierta la app): en ese caso la lista puede estar incompleta.
class ExpensesSnapshot {
  const ExpensesSnapshot(this.expenses, {required this.fromCache});

  final List<SharedExpense> expenses;
  final bool fromCache;
}

/// Id estable del movimiento que refleja tu parte de un gasto compartido.
String splitMovementId(String expenseId) => 'split:$expenseId';

/// Cambios que llevan la wallet a reflejar tu parte de cada gasto compartido.
typedef SplitMovementChanges = ({List<Movement> upsert, List<String> delete});

/// Concilia los movimientos `split` con los gastos compartidos.
///
/// Por cada gasto donde [myUid] tiene una parte mayor que cero hay un gasto en
/// la wallet con solo esa parte. La categoría que el usuario eligió se respeta.
/// Los movimientos sin gasto (o con parte 0) se borran solo si el snapshot
/// viene del servidor: una caché incompleta no debe vaciar la wallet.
/// Es idempotente: solo emite cambios reales.
SplitMovementChanges reconcileSplitMovements({
  required ExpensesSnapshot snapshot,
  required List<Movement> existing,
  required String myUid,
  required Set<String> categoryIds,
}) {
  final byId = {
    for (final m in existing)
      if (m.origin == MovementOrigin.split) m.id: m,
  };
  final upsert = <Movement>[];
  final wanted = <String>{};

  for (final e in snapshot.expenses) {
    final share = e.shareOf(myUid);
    if (share <= 0) continue;
    final id = splitMovementId(e.id);
    wanted.add(id);
    final current = byId[id];
    final others = [
      for (final u in e.participants)
        if (u != myUid) e.people[u]?.shortName ?? 'Amigo',
    ];
    final note =
        'Dividido con ${others.join(', ')} · total ${Fmt.money(Money(e.totalMinor, e.currency))}';
    final categoryId =
        current?.categoryId ??
        (categoryIds.contains(e.categoryId) ? e.categoryId : 'expense_other');
    final desired = Movement(
      id: id,
      kind: MovementKind.expense,
      amount: Money(share, e.currency),
      categoryId: categoryId,
      date: e.date,
      title: e.title,
      // La nota es del usuario si la cambió; solo se regenera la automática.
      note:
          current != null &&
              current.note.isNotEmpty &&
              !current.note.startsWith('Dividido con ')
          ? current.note
          : note,
      origin: MovementOrigin.split,
      createdAt: current?.createdAt ?? e.date,
    );
    if (current == null ||
        current.toJson().toString() != desired.toJson().toString()) {
      upsert.add(desired);
    }
  }

  final delete = snapshot.fromCache
      ? const <String>[]
      : [
          for (final id in byId.keys)
            if (!wanted.contains(id)) id,
        ];
  return (upsert: upsert, delete: delete);
}

/// Gasto compartido que pagaste tú y que quizá ya estaba en tu wallet.
typedef SplitPaymentMatch = ({SharedExpense expense, List<Movement> candidates});

/// Si otra persona reparte un gasto que pagaste tú, tu wallet recibe tu
/// parte (`split`) además del pago que ya registraste (Google Pay, a mano...):
/// se contaría dos veces. Devuelve, por cada uno de esos gastos con tu parte
/// ya en la wallet, los pagos que podrían ser el mismo. Los gastos de
/// [dismissed] (ya respondidos) no se proponen.
List<SplitPaymentMatch> findSplitPaymentMatches({
  required List<SharedExpense> expenses,
  required List<Movement> movements,
  required String myUid,
  required Set<String> dismissed,
}) {
  final splitIds = {
    for (final m in movements)
      if (m.origin == MovementOrigin.split) m.id,
  };
  return [
    for (final e in expenses)
      if (e.paidBy == myUid &&
          e.createdBy != myUid &&
          !dismissed.contains(e.id) &&
          splitIds.contains(splitMovementId(e.id)))
        if (findMatchingPayments(
          movements: movements,
          amountMinor: e.totalMinor,
          merchant: e.title,
          date: e.date,
        )
            case final candidates when candidates.isNotEmpty)
          (expense: e, candidates: candidates),
  ];
}
