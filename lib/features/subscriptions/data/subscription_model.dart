import '../../../core/domain/billing_cycle.dart';
import '../../../core/domain/money.dart';
import '../../merchants/domain/entities/merchant.dart';
import '../../notifications/domain/notification_rule.dart';
import '../domain/entities/subscription.dart';

/// Modelo de persistencia: traduce la entidad de dominio a/desde JSON.
/// `schemaVersion` permite migraciones futuras sin romper datos guardados.
abstract final class SubscriptionModel {
  static const schemaVersion = 1;

  static Map<String, Object?> toJson(Subscription s) => {
        'v': schemaVersion,
        'id': s.id,
        'merchantId': s.merchantId,
        'name': s.name,
        'price': s.price.toJson(),
        'cycle': s.cycle.toJson(),
        'firstChargeDate': s.firstChargeDate.toIso8601String(),
        'category': s.category.name,
        'paymentMethod': s.paymentMethod.toJson(),
        'status': s.status.name,
        'statusChangedAt': s.statusChangedAt?.toIso8601String(),
        'cancellationWindow': s.cancellationWindow?.toJson(),
        'notificationRule': s.notificationRule?.toJson(),
        'notes': s.notes,
        'createdAt': s.createdAt.toIso8601String(),
      };

  static Subscription fromJson(Map<String, Object?> json) {
    Map<String, Object?>? map(String key) => (json[key] as Map?)?.cast<String, Object?>();
    DateTime? date(String key) => json[key] == null ? null : DateTime.parse(json[key] as String);

    return Subscription(
      id: json['id'] as String,
      merchantId: json['merchantId'] as String,
      name: json['name'] as String,
      price: Money.fromJson(map('price')!),
      cycle: BillingCycle.fromJson(map('cycle')!),
      firstChargeDate: date('firstChargeDate')!,
      category: SpendCategory.values.asNameMap()[json['category']] ?? SpendCategory.other,
      paymentMethod: PaymentMethod.fromJson(map('paymentMethod')!),
      status: SubscriptionStatus.values.asNameMap()[json['status']] ?? SubscriptionStatus.active,
      statusChangedAt: date('statusChangedAt'),
      cancellationWindow:
          map('cancellationWindow') == null ? null : CancellationWindow.fromJson(map('cancellationWindow')!),
      notificationRule:
          map('notificationRule') == null ? null : NotificationRule.fromJson(map('notificationRule')!),
      notes: json['notes'] as String? ?? '',
      createdAt: date('createdAt') ?? DateTime.now(),
    );
  }
}
