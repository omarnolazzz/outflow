import 'package:meta/meta.dart';

import '../../../../core/domain/billing_cycle.dart';
import '../../../../core/domain/money.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../notifications/domain/notification_rule.dart';

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
  });

  final String id;
  final String merchantId;

  /// Nombre visible (se copia del comercio al crear; el usuario puede renombrar).
  final String name;
  final Money price;
  final BillingCycle cycle;

  /// Ancla del calendario de cobros (primer cobro o fin de la prueba).
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

  /// Próximo cobro en o después de [now]. null si no está cobrando.
  DateTime? nextCharge(DateTime now) =>
      status.isBilling ? cycle.nextOnOrAfter(firstChargeDate, now) : null;

  /// Último cobro ya efectuado antes de hoy.
  DateTime? lastCharge(DateTime now) => cycle.previousBefore(firstChargeDate, now);

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
        if (!cycle.nextOnOrAfter(firstChargeDate, today).isAfter(today)) today,
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
      );
}
