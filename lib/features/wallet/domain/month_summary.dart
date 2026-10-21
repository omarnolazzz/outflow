import 'package:meta/meta.dart';

import '../../../core/domain/billing_cycle.dart';
import '../../../core/domain/money.dart';
import '../../subscriptions/domain/entities/subscription.dart';
import 'movement.dart';
import 'wallet_settings.dart';

/// Primer día del mes de [d].
DateTime monthOf(DateTime d) => DateTime(d.year, d.month);

DateTime _nextMonth(DateTime m) => DateTime(m.year, m.month + 1);

/// El número de la wallet y lo que lo explica, para un mes.
@immutable
class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.income,
    required this.expense,
    required this.carriedIn,
    required this.remaining,
    required this.afterPending,
    required this.expenseByCategory,
    required this.otherCurrencies,
  });

  /// Primer día del mes.
  final DateTime month;
  final Money income;
  final Money expense;

  /// Sobrante del mes anterior (0 si no aplica).
  final Money carriedIn;

  /// "Te queda este mes" = sobrante + ingresos − gastos.
  final Money remaining;

  /// [remaining] menos los cobros de suscripciones que aún faltan este mes.
  final Money afterPending;
  final Map<String, Money> expenseByCategory;

  /// Neto gastado en monedas distintas de la principal (sin conversión).
  final List<Money> otherCurrencies;

  /// Hay algo con lo que contar este mes (ingresos o sobrante).
  bool get hasIncome => income.minor + carriedIn.minor > 0;

  /// Parte gastada de lo disponible (0–1).
  double get spentRatio {
    final available = income.minor + carriedIn.minor;
    if (available <= 0) return 0;
    return (expense.minor / available).clamp(0.0, 1.0);
  }

  static MonthSummary compute({
    required List<Movement> movements,
    required List<Subscription> subscriptions,
    required WalletSettings settings,
    required DateTime month,
    required DateTime now,
  }) =>
      lastMonths(1, movements: movements, subscriptions: subscriptions, settings: settings, month: month, now: now)
          .single;

  /// Los [n] meses que terminan en [month], del más antiguo al más reciente.
  /// El sobrante se encadena desde el mes en que empezó la wallet.
  static List<MonthSummary> lastMonths(
    int n, {
    required List<Movement> movements,
    required List<Subscription> subscriptions,
    required WalletSettings settings,
    required DateTime month,
    required DateTime now,
  }) {
    final target = monthOf(month);
    final first = DateTime(target.year, target.month - (n - 1));
    final started = settings.walletStartedAt == null ? first : monthOf(settings.walletStartedAt!);
    final cur = settings.currency;

    // Agrupa una sola vez por mes.
    final byMonth = <DateTime, List<Movement>>{};
    for (final m in movements) {
      byMonth.putIfAbsent(monthOf(m.date), () => []).add(m);
    }

    final out = <MonthSummary>[];
    var carry = 0;
    var m = started.isBefore(first) ? started : first;
    while (!m.isAfter(target)) {
      final counted = !m.isBefore(started);
      final s = _build(
        month: m,
        movements: counted ? byMonth[m] ?? const [] : const [],
        carriedIn: counted ? carry : 0,
        currency: cur,
        subscriptions: subscriptions,
        now: now,
      );
      carry = settings.carryOver && s.remaining.minor > 0 ? s.remaining.minor : 0;
      if (!m.isBefore(first)) out.add(s);
      m = _nextMonth(m);
    }
    return out;
  }

  static MonthSummary _build({
    required DateTime month,
    required List<Movement> movements,
    required int carriedIn,
    required String currency,
    required List<Subscription> subscriptions,
    required DateTime now,
  }) {
    var income = 0;
    var expense = 0;
    final byCategory = <String, int>{};
    final others = <String, int>{};
    for (final mv in movements) {
      if (mv.amount.currency != currency) {
        others.update(mv.amount.currency, (v) => v - mv.signedMinor, ifAbsent: () => -mv.signedMinor);
        continue;
      }
      if (mv.isExpense) {
        expense += mv.amount.minor;
        byCategory.update(mv.categoryId, (v) => v + mv.amount.minor, ifAbsent: () => mv.amount.minor);
      } else {
        income += mv.amount.minor;
      }
    }
    final remaining = carriedIn + income - expense;

    return MonthSummary(
      month: month,
      income: Money(income, currency),
      expense: Money(expense, currency),
      carriedIn: Money(carriedIn, currency),
      remaining: Money(remaining, currency),
      afterPending: Money(remaining - _pendingThisMonth(subscriptions, month, currency, now), currency),
      expenseByCategory: {for (final e in byCategory.entries) e.key: Money(e.value, currency)},
      otherCurrencies: [
        for (final e in others.entries)
          if (e.value != 0) Money(e.value, e.key),
      ],
    );
  }

  /// Cobros de suscripciones activas entre mañana y fin de [month] (los de hoy
  /// y anteriores ya son movimientos).
  static int _pendingThisMonth(List<Subscription> subs, DateTime month, String currency, DateTime now) {
    final tomorrow = dateOnly(now).add(const Duration(days: 1));
    final end = _nextMonth(month);
    final from = tomorrow.isAfter(month) ? tomorrow : month;
    if (!from.isBefore(end)) return 0;
    var total = 0;
    for (final s in subs) {
      if (s.status != SubscriptionStatus.active || s.price.currency != currency) continue;
      for (final c in s.chargesFrom(from)) {
        if (!c.isBefore(end)) break;
        total += s.price.minor;
      }
    }
    return total;
  }
}
