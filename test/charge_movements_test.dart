import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/billing_cycle.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/merchants/domain/entities/merchant.dart';
import 'package:outflow/features/notifications/domain/charge_answer.dart';
import 'package:outflow/features/subscriptions/data/subscription_model.dart';
import 'package:outflow/features/subscriptions/domain/apply_charge_answer.dart';
import 'package:outflow/features/subscriptions/domain/entities/subscription.dart';
import 'package:outflow/features/wallet/domain/category.dart';
import 'package:outflow/features/wallet/domain/charge_movements.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';

Subscription netflix({
  DateTime? anchor,
  int minor = 2990,
  SubscriptionStatus status = SubscriptionStatus.active,
  List<ChargeRecord> history = const [],
}) =>
    Subscription(
      id: 'nf',
      merchantId: 'netflix',
      name: 'Netflix',
      price: Money(minor, 'PEN'),
      cycle: const BillingCycle.monthly(),
      firstChargeDate: anchor ?? DateTime(2026, 10, 18),
      category: SpendCategory.streaming,
      paymentMethod: const PaymentMethod(kind: PaymentKind.card),
      createdAt: DateTime(2026, 1, 1),
      status: status,
      chargeHistory: history,
    );

void main() {
  final now = DateTime(2026, 10, 20, 10);
  final settings = WalletSettings(walletStartedAt: DateTime(2026, 10, 5));

  /// Aplica la conciliación sobre [existing] y devuelve el estado resultante.
  List<Movement> run(List<Subscription> subs, List<Movement> existing, {WalletSettings? s, DateTime? at}) {
    final r = reconcileChargeMovements(subscriptions: subs, existing: existing, settings: s ?? settings, now: at ?? now);
    final byId = {for (final m in existing) m.id: m};
    for (final id in r.delete) {
      byId.remove(id);
    }
    for (final m in r.upsert) {
      byId[m.id] = m;
    }
    return byId.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  test('un cobro previsto ayer o antes crea un gasto provisional con id estable', () {
    final out = run([netflix()], const []);
    expect(out, hasLength(1));
    final m = out.single;
    expect(m.id, chargeMovementId('nf', DateTime(2026, 10, 18)));
    expect(m.id, 'sub:nf:2026-10-18');
    expect(m.kind, MovementKind.expense);
    expect(m.amount, const Money(2990, 'PEN'));
    expect(m.categoryId, kSubscriptionsCategoryId);
    expect(m.title, 'Netflix');
    expect(m.origin, MovementOrigin.subscription);
    expect(m.subscriptionId, 'nf');
    expect(m.provisional, isTrue);
    expect(m.date, DateTime(2026, 10, 18));
  });

  test('un cobro de hoy también cuenta; uno de mañana todavía no', () {
    expect(run([netflix(anchor: DateTime(2026, 10, 20))], const []), hasLength(1));
    expect(run([netflix(anchor: DateTime(2026, 10, 21))], const []), isEmpty);
  });

  test('confirmar con otra fecha real mueve el gasto: borra el provisional y crea el confirmado', () {
    final before = run([netflix()], const []);
    final confirmed = netflix().confirmCharge(
      pending: DateTime(2026, 10, 18),
      chargedOn: DateTime(2026, 10, 19),
      next: DateTime(2026, 11, 19),
    );
    final after = run([confirmed], before);
    expect(after.map((m) => m.id), ['sub:nf:2026-10-19']);
    expect(after.single.provisional, isFalse);
  });

  test('confirmar la misma fecha solo quita la marca de provisional', () {
    final before = run([netflix()], const []);
    final confirmed = netflix().confirmCharge(
      pending: DateTime(2026, 10, 18),
      chargedOn: DateTime(2026, 10, 18),
      next: DateTime(2026, 11, 18),
    );
    final after = run([confirmed], before);
    expect(after.single.id, before.single.id);
    expect(after.single.provisional, isFalse);
  });

  test('una prueba gratuita no genera gastos', () {
    expect(run([netflix(status: SubscriptionStatus.trial)], const []), isEmpty);
  });

  test('pausada: conserva los del historial y no crea nuevos', () {
    final s = netflix(
      anchor: DateTime(2026, 11, 8),
      status: SubscriptionStatus.paused,
      history: [ChargeRecord(date: DateTime(2026, 10, 8), confirmed: true)],
    );
    final out = run([s], const []);
    expect(out.map((m) => m.id), ['sub:nf:2026-10-08']);
  });

  test('un cobro borrado por el usuario no se vuelve a crear', () {
    final s = settings.copyWith(deletedChargeIds: {'sub:nf:2026-10-18'});
    expect(run([netflix()], const [], s: s), isEmpty);
  });

  test('un cambio de precio actualiza el provisional salvo que el usuario lo editara', () {
    final created = run([netflix()], const []);
    final repriced = run([netflix(minor: 3490)], created);
    expect(repriced.single.amount, const Money(3490, 'PEN'));

    final edited = [created.single.copyWith(amount: const Money(3100, 'PEN'), userEdited: true)];
    final kept = run([netflix(minor: 3490)], edited);
    expect(kept.single.amount, const Money(3100, 'PEN'));
  });

  test('si se borra la suscripción, sus gastos pasados se quedan', () {
    final created = run([netflix()], const []);
    expect(run(const [], created), hasLength(1));
  });

  test('no cuenta nada anterior al mes en que empezó la wallet', () {
    final s = netflix(anchor: DateTime(2026, 9, 18));
    final out = run([s], const [], s: WalletSettings(walletStartedAt: DateTime(2026, 10, 2)));
    expect(out.map((m) => m.id), ['sub:nf:2026-10-18']);
  });

  test('sin wallet empezada no crea nada', () {
    expect(run([netflix()], const [], s: const WalletSettings()), isEmpty);
  });

  test('es idempotente: aplicada sobre su propia salida no cambia nada', () {
    final once = run([netflix()], const []);
    final r = reconcileChargeMovements(subscriptions: [netflix()], existing: once, settings: settings, now: now);
    expect(r.upsert, isEmpty);
    expect(r.delete, isEmpty);
  });

  group('"Ya la cancelé" desde la notificación', () {
    final pending = DateTime(2026, 10, 18);
    final answer = ChargeAnswer(
      subscriptionId: 'nf',
      charge: pending,
      action: ChargeAnswerAction.cancel,
    );

    test('la suscripción queda cancelada con la pregunta pendiente y el gasto se mantiene', () {
      final created = run([netflix()], const []);
      final cancelled = applyChargeAnswer(netflix(), answer, now)!;
      expect(cancelled.status, SubscriptionStatus.cancelled);
      expect(cancelled.cancelQuestionCharge, pending);
      final out = run([cancelled], created);
      expect(out.single.provisional, isTrue);
    });

    test('"No, la cancelé a tiempo" borra el gasto', () {
      final created = run([netflix()], const []);
      final cancelled = applyChargeAnswer(netflix(), answer, now)!;
      final resolved = cancelled.resolveCancelQuestion(wasCharged: false);
      expect(resolved.cancelQuestionCharge, isNull);
      expect(run([resolved], created), isEmpty);
    });

    test('"Sí, me cobraron" confirma el gasto', () {
      final created = run([netflix()], const []);
      final cancelled = applyChargeAnswer(netflix(), answer, now)!;
      final resolved = cancelled.resolveCancelQuestion(wasCharged: true);
      final out = run([resolved], created);
      expect(out.single.id, 'sub:nf:2026-10-18');
      expect(out.single.provisional, isFalse);
    });
  });

  test('cancelar desde la app tras el cobro: con cobro se confirma; sin cobro se borra', () {
    final created = run([netflix()], const []);
    final pending = DateTime(2026, 10, 18);
    final charged = netflix().cancelAfterCharge(pending, wasCharged: true, now: now);
    expect(charged.status, SubscriptionStatus.cancelled);
    expect(run([charged], created).single.provisional, isFalse);
    final notCharged = netflix().cancelAfterCharge(pending, wasCharged: false, now: now);
    expect(run([notCharged], created), isEmpty);
  });

  test('cancelQuestionCharge sobrevive a JSON', () {
    final s = applyChargeAnswer(
      netflix(),
      ChargeAnswer(subscriptionId: 'nf', charge: DateTime(2026, 10, 18), action: ChargeAnswerAction.cancel),
      now,
    )!;
    expect(SubscriptionModel.fromJson(SubscriptionModel.toJson(s)).cancelQuestionCharge, DateTime(2026, 10, 18));
  });
}
