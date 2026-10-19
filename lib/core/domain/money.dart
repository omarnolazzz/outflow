import 'package:meta/meta.dart';

/// Dinero en unidades menores (centavos) para evitar errores de coma flotante.
@immutable
class Money {
  const Money(this.minor, this.currency);

  factory Money.fromMajor(num amount, String currency) =>
      Money((amount * 100).round(), currency);

  final int minor;

  /// Código ISO 4217 (USD, EUR, MXN…).
  final String currency;

  double get major => minor / 100;

  Money operator +(Money other) {
    assert(other.currency == currency, 'No se suman monedas distintas');
    return Money(minor + other.minor, currency);
  }

  Map<String, Object?> toJson() => {'minor': minor, 'currency': currency};

  factory Money.fromJson(Map<String, Object?> json) =>
      Money((json['minor'] as num).toInt(), json['currency'] as String);

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);
}

const kSupportedCurrencies = ['USD', 'EUR', 'MXN', 'COP', 'ARS', 'CLP', 'PEN', 'GBP', 'BRL'];
