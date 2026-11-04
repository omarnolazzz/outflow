import 'package:meta/meta.dart';

/// Una fila de un estado de cuenta. Dos filas iguales son dos movimientos.
@immutable
class StatementRow {
  const StatementRow({
    required this.date,
    required this.description,
    required this.amountMinor,
    required this.isCredit,
    this.operationId,
  });

  final DateTime date;
  final String description;

  /// Siempre positivo; el sentido lo da [isCredit].
  final int amountMinor;

  /// Entra dinero en la cuenta (importe positivo o columna de abono).
  final bool isCredit;
  final String? operationId;
}

@immutable
class ParsedStatement {
  const ParsedStatement({required this.rows, this.closingBalanceMinor, this.currency});

  final List<StatementRow> rows;

  /// Saldo final que dice el archivo; null si no lo dice (Scotiabank no lo trae).
  final int? closingBalanceMinor;
  final String? currency;
}

/// Lo que dice la cabecera del archivo.
@immutable
class StatementMeta {
  const StatementMeta({this.holder, this.accountDigits, this.from, this.to});

  final String? holder;
  final String? accountDigits;
  final DateTime? from;
  final DateTime? to;
}

/// En qué columna está cada dato. Se indica [amount] (importe con signo), o bien
/// [debit] y/o [credit]. [headerRow] es -1 si las columnas las eligió el usuario.
@immutable
class ColumnMapping {
  const ColumnMapping({
    required this.headerRow,
    required this.date,
    required this.description,
    this.debit,
    this.credit,
    this.amount,
    this.balance,
    this.operationId,
  });

  final int headerRow;
  final int date;
  final int description;
  final int? debit;
  final int? credit;
  final int? amount;
  final int? balance;
  final int? operationId;
}

enum RowKind { expense, income, transfer, fee }

enum RowStatus { fresh, alreadyThere }
