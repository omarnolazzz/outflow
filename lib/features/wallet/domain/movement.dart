import 'package:meta/meta.dart';

import '../../../core/domain/money.dart';

enum MovementKind { expense, income }

/// De dónde salió un movimiento. Los tres últimos se reservan para las fases
/// 2–4 (atajo de Apple Pay, escáner de tickets, gastos divididos).
enum MovementOrigin { manual, subscription, initialBalance, applePay, ticket, split, googlePay }

/// Un gasto o un ingreso. El importe siempre es positivo; el signo lo da [kind].
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

  bool get isExpense => kind == MovementKind.expense;

  /// Los cobros de suscripción son informativos: se ven en el historial, pero
  /// el usuario los paga por su cuenta, así que no descuentan de la wallet.
  bool get countsInWallet => origin != MovementOrigin.subscription;

  /// Importe con signo en unidades menores (gastos negativos).
  int get signedMinor => isExpense ? -amount.minor : amount.minor;

  Movement copyWith({
    MovementKind? kind,
    Money? amount,
    String? categoryId,
    DateTime? date,
    String? title,
    String? note,
    bool? provisional,
    bool? userEdited,
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
      };

  factory Movement.fromJson(Map<String, Object?> json) {
    final date = DateTime.parse(json['date'] as String);
    final created = json['createdAt'] as String?;
    return Movement(
      id: json['id'] as String,
      kind: MovementKind.values.byName(json['kind'] as String),
      amount: Money.fromJson((json['amount'] as Map).cast<String, Object?>()),
      categoryId: json['categoryId'] as String,
      date: date,
      title: json['title'] as String? ?? '',
      note: json['note'] as String? ?? '',
      origin: MovementOrigin.values.asNameMap()[json['origin']] ?? MovementOrigin.manual,
      subscriptionId: json['subscriptionId'] as String?,
      provisional: json['provisional'] as bool? ?? false,
      userEdited: json['userEdited'] as bool? ?? false,
      createdAt: created == null ? date : DateTime.parse(created),
    );
  }
}
