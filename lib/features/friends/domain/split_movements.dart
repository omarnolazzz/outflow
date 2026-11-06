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

/// Id del movimiento con el que saldaste la deuda de [debtor] en un gasto.
String settlementMovementId(String expenseId, String debtor) => 'settle:$expenseId:$debtor';

/// El saldado que refleja [id] (`settle:<gasto>:<deudor>`), o null si no lo es.
({String expenseId, String debtor})? _parseSettlementId(String id) {
  if (!id.startsWith('settle:')) return null;
  final rest = id.substring('settle:'.length);
  final i = rest.lastIndexOf(':');
  if (i <= 0 || i == rest.length - 1) return null;
  return (expenseId: rest.substring(0, i), debtor: rest.substring(i + 1));
}

/// Lo que mueve una cuenta cuando saldas una deuda de un gasto compartido: entra
/// la parte de [debtor] si te paga a ti, sale la tuya si le pagas tú a quien
/// pagó. No cuenta en el Resumen (tu parte ya contó al repartir el gasto). Null
/// sin [accountId], o si no intervienes en esa deuda.
Movement? makeSettlementMovement({
  required SharedExpense e,
  required String debtor,
  required String me,
  String? accountId,
  required DateTime now,
}) {
  if (accountId == null) return null;
  final int signed;
  if (debtor == me) {
    if (e.paidBy == me) return null;
    signed = -e.shareOf(me);
  } else {
    if (e.paidBy != me) return null;
    signed = e.shareOf(debtor);
  }
  if (signed == 0) return null;
  final other = debtor == me ? e.people[e.paidBy]?.shortName : e.people[debtor]?.shortName;
  return Movement(
    id: settlementMovementId(e.id, debtor),
    kind: MovementKind.adjustment,
    amount: Money(signed.abs(), e.currency),
    categoryId: kNoCategoryId,
    date: now,
    createdAt: now,
    title: e.title,
    note: debtor == me ? 'Pagaste a ${other ?? 'Amigo'}' : '${other ?? 'Amigo'} te pagó',
    origin: MovementOrigin.settlement,
    accountId: accountId,
    adjustmentMinor: signed,
  );
}

/// Cambios que llevan la wallet a reflejar tu parte de cada gasto compartido.
typedef SplitMovementChanges = ({List<Movement> upsert, List<String> delete});

/// Concilia los movimientos `split` con los gastos compartidos.
///
/// Por cada gasto donde [myUid] tiene una parte mayor que cero hay un gasto en
/// la wallet con solo esa parte. La categoría que el usuario eligió se respeta.
/// Los movimientos sin gasto (o con parte 0) se borran solo si el snapshot
/// viene del servidor: una caché incompleta no debe vaciar la wallet. Lo mismo
/// vale para los saldados (`settle:`) cuya deuda ya no figura como pagada.
///
/// Si pagaste tú, la cuenta pierde el total y no solo tu parte ([Movement.paidMinor]);
/// si pagó otro, no se mueve. Un `split` creado antes de esto (sin `paidMinor`)
/// sigue moviendo solo tu parte. Al crearse, `createdAt` es [now] y no la fecha
/// del gasto: así un reparto antiguo que llega tras un ajuste de saldo queda
/// cubierto por ese ajuste en vez de bajar la cuenta otra vez.
/// Es idempotente: solo emite cambios reales.
SplitMovementChanges reconcileSplitMovements({
  required ExpensesSnapshot snapshot,
  required List<Movement> existing,
  required String myUid,
  required Set<String> categoryIds,
  required DateTime now,
  Map<String, String> splitAccountIds = const {},
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
      createdAt: current?.createdAt ?? now,
      // Lo que el usuario o la captura ataron a este pago no sale del reparto.
      accountId: current == null ? splitAccountIds[e.id] : current.accountId,
      paidMinor: current == null || current.paidMinor != null ? (e.paidBy == myUid ? e.totalMinor : 0) : null,
      needsReview: current?.needsReview ?? false,
      externalRef: current?.externalRef,
      pairedCaptureId: current?.pairedCaptureId,
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
          for (final m in existing)
            if (m.origin == MovementOrigin.settlement && _settlementGone(m.id, snapshot.expenses)) m.id,
        ];
  return (upsert: upsert, delete: delete);
}

/// El saldado [id] ya no existe en el servidor: el gasto se borró o se editó
/// de modo que esa deuda dejó de estar pagada.
bool _settlementGone(String id, List<SharedExpense> expenses) {
  final parsed = _parseSettlementId(id);
  if (parsed == null) return false;
  final e = expenses.where((x) => x.id == parsed.expenseId).firstOrNull;
  return e == null || !e.isSettled(parsed.debtor);
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
