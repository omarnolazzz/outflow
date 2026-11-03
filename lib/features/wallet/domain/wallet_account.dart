import 'package:meta/meta.dart';

enum AccountType { bank, wallet, cash, creditCard, other }

/// Id fijo de la cuenta creada automáticamente: dos creaciones a la vez
/// escriben el mismo documento, así que nunca pueden dejar dos cuentas.
const kDefaultAccountId = 'default';

/// `initialDate` de una cuenta que cuenta todo el historial, sin importar lo
/// antiguo que sea.
final kAccountBeginning = DateTime.fromMillisecondsSinceEpoch(0);

/// Una cuenta con saldo: banco, billetera, efectivo, tarjeta de crédito u otra.
/// Su saldo es [initialMinor] más el efecto de sus movimientos desde
/// [initialDate] (ver `computeBalances`).
@immutable
class WalletAccount {
  const WalletAccount({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    required this.initialMinor,
    required this.initialDate,
    this.lastDigits,
    this.isDefault = false,
    this.archived = false,
  });

  final String id;
  final String name;
  final AccountType type;

  /// Código ISO 4217: la cuenta solo cuenta movimientos en esta moneda.
  final String currency;

  /// Saldo en [initialDate], en unidades menores (en una tarjeta de crédito, lo
  /// que se debe es negativo).
  final int initialMinor;

  /// Lo anterior a este instante ya está dentro de [initialMinor].
  final DateTime initialDate;
  final String? lastDigits;

  /// Recibe los movimientos que no indican cuenta. No se puede archivar.
  final bool isDefault;

  /// Oculta y fuera de los totales; sus movimientos se conservan.
  final bool archived;

  WalletAccount copyWith({
    String? name,
    AccountType? type,
    String? currency,
    int? initialMinor,
    DateTime? initialDate,
    String? lastDigits,
    bool? isDefault,
    bool? archived,
  }) =>
      WalletAccount(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        currency: currency ?? this.currency,
        initialMinor: initialMinor ?? this.initialMinor,
        initialDate: initialDate ?? this.initialDate,
        lastDigits: lastDigits ?? this.lastDigits,
        isDefault: isDefault ?? this.isDefault,
        archived: archived ?? this.archived,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'currency': currency,
        'initialMinor': initialMinor,
        'initialDate': initialDate.toIso8601String(),
        'lastDigits': lastDigits,
        'isDefault': isDefault,
        'archived': archived,
      };

  factory WalletAccount.fromJson(Map<String, Object?> json) => WalletAccount(
        id: json['id'] as String,
        name: json['name'] as String,
        type: AccountType.values.asNameMap()[json['type']] ?? AccountType.other,
        currency: json['currency'] as String,
        initialMinor: (json['initialMinor'] as num).toInt(),
        initialDate: DateTime.parse(json['initialDate'] as String),
        lastDigits: json['lastDigits'] as String?,
        isDefault: json['isDefault'] as bool? ?? false,
        archived: json['archived'] as bool? ?? false,
      );
}

/// "Mi cuenta": saldo inicial 0 desde [kAccountBeginning], porque el saldo de
/// quien ya tenía datos sale de todo su historial (el "Saldo inicial" del
/// onboarding ya es un movimiento).
WalletAccount newDefaultAccount(String currency) => WalletAccount(
      id: kDefaultAccountId,
      name: 'Mi cuenta',
      type: AccountType.other,
      currency: currency,
      initialMinor: 0,
      initialDate: kAccountBeginning,
      isDefault: true,
    );

/// La cuenta por defecto; si ninguna está marcada, la primera sin archivar.
WalletAccount? defaultAccountOf(Iterable<WalletAccount> accounts) =>
    accounts.where((a) => a.isDefault).firstOrNull ??
    accounts.where((a) => !a.archived).firstOrNull ??
    accounts.firstOrNull;

/// Orden estable: la cuenta por defecto y luego por nombre.
List<WalletAccount> sortAccounts(Iterable<WalletAccount> accounts) => accounts.toList()
  ..sort((a, b) {
    if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
