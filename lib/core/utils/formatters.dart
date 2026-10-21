import 'package:intl/intl.dart';

import '../domain/billing_cycle.dart';
import '../domain/money.dart';

abstract final class Fmt {
  /// Locale regional resuelto en `main()` (p. ej. es_MX → "$15.49", es_ES → "15,49 $").
  static String get locale => Intl.getCurrentLocale();

  /// Elige la variante de español según la región del dispositivo. Las
  /// regiones sin datos propios en `intl` usan es_419 (Latinoamérica).
  static String resolveLocale(String? countryCode) => switch (countryCode) {
        'ES' => 'es_ES',
        'MX' => 'es_MX',
        'US' => 'es_US',
        _ => 'es_419',
      };

  static final _money = <String, NumberFormat>{};

  /// Símbolos sin ambigüedad para monedas extranjeras: en México "$" es el
  /// peso, así que el dólar se muestra "US$".
  static const _foreignSymbols = {
    'USD': 'US\$', 'MXN': 'MX\$', 'COP': 'COL\$', 'ARS': 'AR\$', 'CLP': 'CLP\$',
    'EUR': '€', 'GBP': '£', 'PEN': 'S/', 'BRL': 'R\$',
  };

  /// Símbolo con el que se muestra [currency] ("S/", "US$", "€").
  static String symbol(String currency) {
    final local = NumberFormat.simpleCurrency(locale: locale).currencyName;
    if (currency == local) return NumberFormat.simpleCurrency(locale: locale, name: currency).currencySymbol;
    return _foreignSymbols[currency] ?? currency;
  }

  /// Separador decimal del locale ("." o ",").
  static String get decimalSeparator => NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;

  static String money(Money m) {
    final f = _money.putIfAbsent('$locale|${m.currency}', () {
      final local = NumberFormat.simpleCurrency(locale: locale).currencyName;
      final native = NumberFormat.simpleCurrency(locale: locale, name: m.currency);
      if (m.currency == local) return native;
      return NumberFormat.currency(
        locale: locale,
        name: m.currency,
        symbol: _foreignSymbols[m.currency] ?? '${m.currency} ',
        decimalDigits: native.decimalDigits,
      );
    });
    return f.format(m.major);
  }

  /// "21 oct"
  static String dateShort(DateTime d) => DateFormat('d MMM', locale).format(d).replaceAll('.', '');

  /// "miércoles, 21 oct 2026" (filas "Se renueva el").
  static String dateMedium(DateTime d) =>
      DateFormat('EEEE, d MMM y', locale).format(d).replaceAll('.', '');

  /// "martes, 21 de octubre de 2026"
  static String dateLong(DateTime d) => DateFormat("EEEE, d 'de' MMMM 'de' y", locale).format(d);

  /// "09:00"
  static String time(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// "Hoy", "Mañana", "En 5 días", "Ayer", "Hace 3 días".
  static String relativeDays(int days) => switch (days) {
        0 => 'Hoy',
        1 => 'Mañana',
        -1 => 'Ayer',
        > 1 => 'En $days días',
        _ => 'Hace ${-days} días',
      };

  static String cycle(BillingCycle c) {
    if (c.every == 1) {
      return switch (c.unit) {
        CycleUnit.day => 'Diario',
        CycleUnit.week => 'Semanal',
        CycleUnit.month => 'Mensual',
        CycleUnit.year => 'Anual',
      };
    }
    if (c.unit == CycleUnit.month && c.every == 3) return 'Trimestral';
    if (c.unit == CycleUnit.month && c.every == 6) return 'Semestral';
    final unit = switch (c.unit) {
      CycleUnit.day => 'días',
      CycleUnit.week => 'semanas',
      CycleUnit.month => 'meses',
      CycleUnit.year => 'años',
    };
    return 'Cada ${c.every} $unit';
  }

  static String unitLabel(CycleUnit u, {bool plural = false}) => switch (u) {
        CycleUnit.day => plural ? 'días' : 'día',
        CycleUnit.week => plural ? 'semanas' : 'semana',
        CycleUnit.month => plural ? 'meses' : 'mes',
        CycleUnit.year => plural ? 'años' : 'año',
      };

  static String days(int n) => n == 1 ? '1 día' : '$n días';
}
