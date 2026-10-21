import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/wallet/domain/category.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';

void main() {
  final full = Movement(
    id: 'm1',
    kind: MovementKind.expense,
    amount: const Money(2990, 'PEN'),
    categoryId: kSubscriptionsCategoryId,
    date: DateTime(2026, 10, 18),
    title: 'Netflix',
    note: 'plan estándar',
    origin: MovementOrigin.subscription,
    subscriptionId: 's1',
    provisional: true,
    userEdited: true,
    createdAt: DateTime(2026, 10, 18, 9),
  );

  test('Movement sobrevive a JSON con todos los campos', () {
    final back = Movement.fromJson(full.toJson());
    expect(back.toJson(), full.toJson());
    expect(back.subscriptionId, 's1');
    expect(back.provisional, isTrue);
    expect(back.userEdited, isTrue);
  });

  test('Movement.fromJson acepta JSON mínimo', () {
    final m = Movement.fromJson({
      'id': 'm2',
      'kind': 'income',
      'amount': {'minor': 100000, 'currency': 'PEN'},
      'categoryId': 'salary',
      'date': '2026-10-01T00:00:00.000',
    });
    expect(m.kind, MovementKind.income);
    expect(m.title, '');
    expect(m.note, '');
    expect(m.origin, MovementOrigin.manual);
    expect(m.provisional, isFalse);
    expect(m.userEdited, isFalse);
    expect(m.subscriptionId, isNull);
  });

  test('signedMinor: gastos restan e ingresos suman', () {
    expect(full.signedMinor, -2990);
    expect(full.copyWith(kind: MovementKind.income).signedMinor, 2990);
  });

  test('defaultCategories: 11 gastos, 5 ingresos y una reservada para suscripciones', () {
    final c = defaultCategories();
    expect(c.where((x) => x.kind == MovementKind.expense).length, 11);
    expect(c.where((x) => x.kind == MovementKind.income).length, 5);
    expect(c.singleWhere((x) => x.reserved).id, kSubscriptionsCategoryId);
    expect(c.map((x) => x.id).toSet().length, c.length, reason: 'ids únicos');
  });

  test('Category sobrevive a JSON', () {
    final c = defaultCategories().first;
    expect(Category.fromJson(c.toJson()).toJson(), c.toJson());
  });

  test('WalletSettings por defecto: PEN, sobrante activo, configuración pendiente', () {
    const s = WalletSettings();
    expect(s.currency, 'PEN');
    expect(s.carryOver, isTrue);
    expect(s.onboardingDone, isFalse);
    expect(s.faceIdEnabled, isFalse);
    expect(s.walletStartedAt, isNull);
    expect(s.deletedChargeIds, isEmpty);
  });

  test('WalletSettings sobrevive a JSON y lee JSON vacío', () {
    final s = WalletSettings(
      currency: 'USD',
      carryOver: false,
      walletStartedAt: DateTime(2026, 10, 1),
      onboardingDone: true,
      faceIdEnabled: true,
      deletedChargeIds: const {'sub:s1:2026-10-18'},
    );
    expect(WalletSettings.fromJson(s.toJson()).toJson(), s.toJson());
    expect(WalletSettings.fromJson(const {}).toJson(), const WalletSettings().toJson());
  });
}
