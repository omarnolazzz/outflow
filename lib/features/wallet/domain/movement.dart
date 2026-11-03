import 'package:meta/meta.dart';

import '../../../core/domain/money.dart';

/// Los tipos se guardan por nombre: no se renombran.
enum MovementKind { expense, income, transfer, adjustment }

/// De dónde salió un movimiento (se guarda por nombre). [settlement] es saldar
/// una deuda con un amigo; [capture], un aviso leído por la captura automática;
/// [statement], una fila de un estado de cuenta importado.
enum MovementOrigin {
  manual,
  subscription,
  initialBalance,
  applePay,
  ticket,
  split,
  googlePay,
  settlement,
  capture,
  statement,
}

/// `categoryId` de lo que no tiene categoría (transferencias y ajustes): no
/// corresponde a ninguna, así que al buscarla el resultado es null.
const kNoCategoryId = '';

/// Un gasto, un ingreso, una transferencia entre cuentas propias o un ajuste de
/// saldo. El importe siempre es positivo; el signo lo da [kind].
@immutable
class Movement {
  const Movement({
    required this.id,
    required this.kind,
    required this.amount,
    required this.categoryId,
    required this.date,
    required this.createdAt,
    this.title = '',
    this.note = '',
    this.origin = MovementOrigin.manual,
    this.subscriptionId,
    this.provisional = false,
    this.userEdited = false,
    this.accountId,
    this.toAccountId,
    this.transferIncoming = false,
    this.receivedMinor,
    this.adjustmentMinor,
    this.paidMinor,
    this.needsReview = false,
    this.externalRef,
    this.pairedCaptureId,
  });

  final String id;
  final MovementKind kind;
  final Money amount;
  final String categoryId;
  final DateTime date;

  /// Comercio o concepto ("Netflix", "Almuerzo").
  final String title;
  final String note;
  final MovementOrigin origin;

  /// Suscripción que generó el cobro (origen [MovementOrigin.subscription]).
  final String? subscriptionId;

  /// Cobro de suscripción previsto, aún sin confirmar.
  final bool provisional;

  /// El usuario cambió a mano un movimiento automático: no se sobrescribe.
  final bool userEdited;
  final DateTime createdAt;

  /// Cuenta del movimiento (el origen, en una transferencia). Null = la cuenta
  /// por defecto: así se leen los movimientos anteriores a las cuentas.
  final String? accountId;

  /// Cuenta destino de una transferencia.
  final String? toAccountId;

  /// Transferencia cuyo otro lado es una cuenta propia aún no registrada
  /// ([toAccountId] null): true = entra en [accountId], false = sale.
  final bool transferIncoming;

  /// Lo que recibe el destino de una transferencia, en su moneda (null = [amount]).
  final int? receivedMinor;

  /// Diferencia con signo de un ajuste de saldo.
  final int? adjustmentMinor;

  /// Lo que salió de verdad de la cuenta en un gasto (null = [amount]): pagaste
  /// 100 entre 4 → [amount] es tu parte (25) y aquí van los 100.
  final int? paidMinor;

  /// Creado sin confirmar: el usuario debería revisarlo.
  final bool needsReview;

  /// Referencia de la operación en el banco o la entidad de origen.
  final String? externalRef;

  /// Id del evento de captura fundido con este movimiento: otro rastro del mismo
  /// pago. Solo se absorbe uno, y así reprocesarlo no lo cuenta de nuevo.
  final String? pairedCaptureId;

  bool get isExpense => kind == MovementKind.expense;

  /// Mueve dinero entre cuentas o corrige un saldo: ni gasto ni ingreso.
  bool get isTransferOrAdjustment => kind == MovementKind.transfer || kind == MovementKind.adjustment;

  /// Solo gastos e ingresos cuentan en "Te queda" y el Resumen. Los cobros de
  /// suscripción son informativos: se ven en el historial, pero el usuario los
  /// paga por su cuenta. Saldar una deuda mueve una cuenta, no la wallet.
  bool get countsInWallet =>
      !isTransferOrAdjustment && origin != MovementOrigin.subscription && origin != MovementOrigin.settlement;

  /// Importe con signo en unidades menores (gastos negativos). Una transferencia
  /// es neutra: lo que sale de una cuenta entra en otra.
  int get signedMinor => switch (kind) {
        MovementKind.expense => -amount.minor,
        MovementKind.income => amount.minor,
        MovementKind.adjustment => adjustmentMinor ?? 0,
        MovementKind.transfer => 0,
      };

  Movement copyWith({
    MovementKind? kind,
    Money? amount,
    String? categoryId,
    DateTime? date,
    String? title,
    String? note,
    bool? provisional,
    bool? userEdited,
    String? accountId,
    String? toAccountId,
    bool? transferIncoming,
    int? receivedMinor,
    int? adjustmentMinor,
    int? paidMinor,
    bool? needsReview,
    String? externalRef,
    String? pairedCaptureId,
  }) =>
      Movement(
        id: id,
        kind: kind ?? this.kind,
        amount: amount ?? this.amount,
        categoryId: categoryId ?? this.categoryId,
        date: date ?? this.date,
        title: title ?? this.title,
        note: note ?? this.note,
        origin: origin,
        subscriptionId: subscriptionId,
        provisional: provisional ?? this.provisional,
        userEdited: userEdited ?? this.userEdited,
        createdAt: createdAt,
        accountId: accountId ?? this.accountId,
        toAccountId: toAccountId ?? this.toAccountId,
        transferIncoming: transferIncoming ?? this.transferIncoming,
        receivedMinor: receivedMinor ?? this.receivedMinor,
        adjustmentMinor: adjustmentMinor ?? this.adjustmentMinor,
        paidMinor: paidMinor ?? this.paidMinor,
        needsReview: needsReview ?? this.needsReview,
        externalRef: externalRef ?? this.externalRef,
        pairedCaptureId: pairedCaptureId ?? this.pairedCaptureId,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'amount': amount.toJson(),
        'categoryId': categoryId,
        'date': date.toIso8601String(),
        'title': title,
        'note': note,
        'origin': origin.name,
        'subscriptionId': subscriptionId,
        'provisional': provisional,
        'userEdited': userEdited,
        'createdAt': createdAt.toIso8601String(),
        'accountId': accountId,
        'toAccountId': toAccountId,
        'transferIncoming': transferIncoming,
        'receivedMinor': receivedMinor,
        'adjustmentMinor': adjustmentMinor,
        'paidMinor': paidMinor,
        'needsReview': needsReview,
        'externalRef': externalRef,
        'pairedCaptureId': pairedCaptureId,
      };

  factory Movement.fromJson(Map<String, Object?> json) {
    final date = DateTime.parse(json['date'] as String);
    final created = json['createdAt'] as String?;
    return Movement(
      id: json['id'] as String,
      kind: MovementKind.values.byName(json['kind'] as String),
      amount: Money.fromJson((json['amount'] as Map).cast<String, Object?>()),
      categoryId: json['categoryId'] as String? ?? kNoCategoryId,
      date: date,
      title: json['title'] as String? ?? '',
      note: json['note'] as String? ?? '',
      origin: MovementOrigin.values.asNameMap()[json['origin']] ?? MovementOrigin.manual,
      subscriptionId: json['subscriptionId'] as String?,
      provisional: json['provisional'] as bool? ?? false,
      userEdited: json['userEdited'] as bool? ?? false,
      createdAt: created == null ? date : DateTime.parse(created),
      accountId: json['accountId'] as String?,
      toAccountId: json['toAccountId'] as String?,
      transferIncoming: json['transferIncoming'] as bool? ?? false,
      receivedMinor: (json['receivedMinor'] as num?)?.toInt(),
      adjustmentMinor: (json['adjustmentMinor'] as num?)?.toInt(),
      paidMinor: (json['paidMinor'] as num?)?.toInt(),
      needsReview: json['needsReview'] as bool? ?? false,
      externalRef: json['externalRef'] as String?,
      pairedCaptureId: json['pairedCaptureId'] as String?,
    );
  }
}
