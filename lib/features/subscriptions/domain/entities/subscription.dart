import 'package:meta/meta.dart';

import '../../../../core/domain/billing_cycle.dart';
import '../../../../core/domain/money.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../notifications/domain/notification_rule.dart';
import '../charge_pattern.dart';
import '../charge_schedule.dart';

enum SubscriptionStatus {
  active('Activa'),
  trial('Prueba gratuita'),
  paused('Pausada'),
  cancelled('Cancelada');

  const SubscriptionStatus(this.label);
  final String label;

  /// Estados que generan cobros y recordatorios.
  bool get isBilling => this == active || this == trial;
}

enum PaymentKind {
  card('Tarjeta'),
  bank('Cuenta bancaria'),
  paypal('PayPal'),
  carrier('Factura del operador'),
  appStore('App Store / Google Play'),
  other('Otro');

  const PaymentKind(this.label);
  final String label;
}

@immutable
class PaymentMethod {
  const PaymentMethod({required this.kind, this.label = '', this.last4});

  final PaymentKind kind;

  /// Nombre libre: "Visa Nubank", "BBVA nómina"…
  final String label;
  final String? last4;

  String get display {
    final name = label.isEmpty ? kind.label : label;
    return last4 == null || last4!.isEmpty ? name : '$name ·· $last4';
  }

  Map<String, Object?> toJson() => {'kind': kind.name, 'label': label, 'last4': last4};

  factory PaymentMethod.fromJson(Map<String, Object?> json) => PaymentMethod(
        kind: PaymentKind.values.byName(json['kind'] as String),
        label: json['label'] as String? ?? '',
        last4: json['last4'] as String?,
      );
}

enum CancellationPolicy {
  /// El comercio permite cancelar (y pedir reembolso) N días DESPUÉS del cobro.
  afterCharge,

  /// Hay que avisar N días ANTES del cobro para que no se renueve.
  beforeCharge,
}

/// Plazo que da el comercio para cancelar alrededor del cobro automático.
@immutable
class CancellationWindow {
  const CancellationWindow({required this.days, this.policy = CancellationPolicy.afterCharge})
      : assert(days >= 0);

  final int days;
  final CancellationPolicy policy;

  /// Último día para cancelar respecto a un cobro concreto.
  DateTime deadlineFor(DateTime chargeDate) {
    final d = dateOnly(chargeDate);
    return policy == CancellationPolicy.afterCharge
        ? DateTime(d.year, d.month, d.day + days)
        : DateTime(d.year, d.month, d.day - days);
  }

  Map<String, Object?> toJson() => {'days': days, 'policy': policy.name};

  factory CancellationWindow.fromJson(Map<String, Object?> json) => CancellationWindow(
        days: (json['days'] as num).toInt(),
        policy: CancellationPolicy.values.byName(json['policy'] as String? ?? 'afterCharge'),
      );
}

/// Ventana abierta en este momento (para el callout del detalle y el dashboard).
@immutable
class OpenCancellationWindow {
  const OpenCancellationWindow({required this.chargeDate, required this.deadline});
  final DateTime chargeDate;
  final DateTime deadline;
}

/// Cobro ya pasado: confirmado por el usuario o asumido por falta de respuesta.
@immutable
class ChargeRecord {
  const ChargeRecord({required this.date, required this.confirmed});

  final DateTime date;

  /// Solo los confirmados enseñan el patrón.
  final bool confirmed;

  Map<String, Object?> toJson() => {'date': date.toIso8601String(), 'confirmed': confirmed};

  factory ChargeRecord.fromJson(Map<String, Object?> json) => ChargeRecord(
        date: dateOnly(DateTime.parse(json['date'] as String)),
        confirmed: json['confirmed'] as bool? ?? false,
      );
}

@immutable
class Subscription {
  const Subscription({
    required this.id,
    required this.merchantId,
    required this.name,
    required this.price,
    required this.cycle,
    required this.firstChargeDate,
    required this.category,
    required this.paymentMethod,
    required this.createdAt,
    this.status = SubscriptionStatus.active,
    this.statusChangedAt,
    this.cancellationWindow,
    this.notificationRule,
    this.notes = '',
    this.chargeHistory = const [],
    this.chargePattern,
    this.cancelQuestionCharge,
  });

  final String id;
  final String merchantId;

  /// Nombre visible (se copia del comercio al crear; el usuario puede renombrar).
  final String name;
  final Money price;
  final BillingCycle cycle;

  /// Ancla del calendario: el próximo cobro introducido al registrar o la
  /// fecha elegida en la última confirmación. Los siguientes se proyectan
  /// desde aquí con [pattern].
  final DateTime firstChargeDate;
  final SpendCategory category;
  final PaymentMethod paymentMethod;
  final SubscriptionStatus status;
  final DateTime? statusChangedAt;
  final CancellationWindow? cancellationWindow;

  /// null → usa la regla global de notificaciones.
  final NotificationRule? notificationRule;
  final String notes;
  final DateTime createdAt;

  /// Cobros pasados (ordenados), confirmados o asumidos.
  final List<ChargeRecord> chargeHistory;

  /// Patrón aprendido o elegido. null → mismo día del mes que el ancla
  /// (el comportamiento de siempre, también para datos antiguos).
  final ChargePattern? chargePattern;

  /// "Ya la cancelé" pulsado en la notificación tras este cobro: falta saber
  /// si se llegó a cobrar ("¿Te llegaron a cobrar este mes?").
  final DateTime? cancelQuestionCharge;

  ChargePattern get pattern => chargePattern ?? ChargePattern.sameDay(firstChargeDate.day);

  /// Cobros proyectados desde el ancla, en o después de [from] (perezoso, infinito).
  Iterable<DateTime> chargesFrom(DateTime from) sync* {
    final f = dateOnly(from);
    final p = pattern;
    var c = dateOnly(firstChargeDate);
    while (c.isBefore(f)) {
      c = p.nextAfter(c, cycle);
    }
    while (true) {
      yield c;
      c = p.nextAfter(c, cycle);
    }
  }

  /// Último cobro proyectado desde el ancla estrictamente antes de [day].
  DateTime? _lastProjectedBefore(DateTime day) {
    final d = dateOnly(day);
    var c = dateOnly(firstChargeDate);
    if (!c.isBefore(d)) return null;
    final p = pattern;
    while (true) {
      final n = p.nextAfter(c, cycle);
      if (!n.isBefore(d)) return c;
      c = n;
    }
  }

  /// Próximo cobro en o después de [now]. null si no está cobrando.
  DateTime? nextCharge(DateTime now) => status.isBilling ? chargesFrom(now).first : null;

  /// Último cobro ya efectuado antes de hoy (historial o proyección).
  DateTime? lastCharge(DateTime now) {
    final today = dateOnly(now);
    final fromHistory = chargeHistory.where((r) => r.date.isBefore(today)).map((r) => r.date);
    final candidates = [...fromHistory, ?_lastProjectedBefore(today)];
    if (candidates.isEmpty) return null;
    return candidates.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Cobro previsto que ya pasó y aún no se ha confirmado (como mucho uno: el
  /// más reciente). Se pregunta desde el día siguiente al cobro.
  DateTime? pendingCharge(DateTime now) =>
      status.isBilling ? _lastProjectedBefore(now) : null;

  /// Registra la respuesta a la pregunta del cobro [pending]: los ciclos
  /// anteriores sin respuesta pasan al historial como asumidos, [chargedOn]
  /// como confirmado, y [next] se convierte en el nuevo ancla.
  ///
  /// [pattern] es el de la sugerencia elegida; con una fecha propia se infiere
  /// del historial o, si no hay bastante, se reajusta el día del patrón actual.
  Subscription confirmCharge({
    required DateTime pending,
    required DateTime chargedOn,
    required DateTime next,
    ChargePattern? pattern,
  }) {
    final p = dateOnly(pending);
    final assumed = <ChargeRecord>[];
    for (final c in chargesFrom(firstChargeDate)) {
      if (!c.isBefore(p)) break;
      assumed.add(ChargeRecord(date: c, confirmed: false));
    }
    final history = [
      ...chargeHistory,
      ...assumed,
      ChargeRecord(date: dateOnly(chargedOn), confirmed: true),
    ]..sort((a, b) => a.date.compareTo(b.date));
    // Suficiente para aprender el patrón sin crecer sin límite.
    final trimmed = history.length > 24 ? history.sublist(history.length - 24) : history;

    final nextDate = dateOnly(next);
    return copyWith(
      firstChargeDate: nextDate,
      chargeHistory: trimmed,
      chargePattern: pattern ?? inferPattern(trimmed, cycle) ?? this.pattern.withDayOf(nextDate),
    );
  }

  /// Responde "¿Te llegaron a cobrar este mes?" tras cancelar desde la
  /// notificación: si hubo cobro queda en el historial como confirmado.
  Subscription resolveCancelQuestion({required bool wasCharged}) {
    final q = cancelQuestionCharge;
    if (q == null) return this;
    return copyWith(
      clearCancelQuestion: true,
      chargeHistory: wasCharged ? _withConfirmed(q) : null,
    );
  }

  /// "Ya la cancelé" en la app después del cobro [pending], sabiendo ya si se cobró.
  Subscription cancelAfterCharge(DateTime pending, {required bool wasCharged, required DateTime now}) =>
      copyWith(
        status: SubscriptionStatus.cancelled,
        statusChangedAt: now,
        clearCancelQuestion: true,
        chargeHistory: wasCharged ? _withConfirmed(dateOnly(pending)) : null,
      );

  List<ChargeRecord> _withConfirmed(DateTime date) => [
        for (final r in chargeHistory)
          if (r.date != date) r,
        ChargeRecord(date: date, confirmed: true),
      ]..sort((a, b) => a.date.compareTo(b.date));

  int? daysUntilCharge(DateTime now) {
    final next = nextCharge(now);
    return next?.difference(dateOnly(now)).inDays;
  }

  /// Ventana de cancelación abierta hoy, si la hay.
  ///
  /// - afterCharge: abierta desde el último cobro hasta cobro + N días.
  /// - beforeCharge: "abierta" hasta N días antes del próximo cobro.
  OpenCancellationWindow? openWindow(DateTime now) {
    final w = cancellationWindow;
    if (w == null || status == SubscriptionStatus.cancelled) return null;
    final today = dateOnly(now);

    if (w.policy == CancellationPolicy.afterCharge) {
      // Un cobro de hoy cuenta como "ya efectuado".
      final charges = [
        if (!chargesFrom(today).first.isAfter(today)) today,
        ?lastCharge(today),
      ];
      for (final c in charges) {
        final deadline = w.deadlineFor(c);
        if (!deadline.isBefore(today)) {
          return OpenCancellationWindow(chargeDate: c, deadline: deadline);
        }
      }
      return null;
    }

    final next = nextCharge(now);
    if (next == null) return null;
    final deadline = w.deadlineFor(next);
    return deadline.isBefore(today) ? null : OpenCancellationWindow(chargeDate: next, deadline: deadline);
  }

  /// Gasto equivalente mensual (en unidades menores) para totales del dashboard.
  int get monthlyMinor => (price.minor * cycle.monthlyFactor).round();

  Subscription copyWith({
    String? merchantId,
    String? name,
    Money? price,
    BillingCycle? cycle,
    DateTime? firstChargeDate,
    SpendCategory? category,
    PaymentMethod? paymentMethod,
    SubscriptionStatus? status,
    DateTime? statusChangedAt,
    CancellationWindow? cancellationWindow,
    bool clearCancellationWindow = false,
    NotificationRule? notificationRule,
    bool clearNotificationRule = false,
    String? notes,
    List<ChargeRecord>? chargeHistory,
    ChargePattern? chargePattern,
    DateTime? cancelQuestionCharge,
    bool clearCancelQuestion = false,
  }) =>
      Subscription(
        id: id,
        merchantId: merchantId ?? this.merchantId,
        name: name ?? this.name,
        price: price ?? this.price,
        cycle: cycle ?? this.cycle,
        firstChargeDate: firstChargeDate ?? this.firstChargeDate,
        category: category ?? this.category,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        status: status ?? this.status,
        statusChangedAt: statusChangedAt ?? this.statusChangedAt,
        cancellationWindow:
            clearCancellationWindow ? null : (cancellationWindow ?? this.cancellationWindow),
        notificationRule:
            clearNotificationRule ? null : (notificationRule ?? this.notificationRule),
        notes: notes ?? this.notes,
        createdAt: createdAt,
        chargeHistory: chargeHistory ?? this.chargeHistory,
        chargePattern: chargePattern ?? this.chargePattern,
        cancelQuestionCharge:
            clearCancelQuestion ? null : (cancelQuestionCharge ?? this.cancelQuestionCharge),
      );
}
