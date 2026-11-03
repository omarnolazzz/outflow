import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/wallet/domain/category.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
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

  test('signedMinor: un ajuste lleva su signo y una transferencia es neutra', () {
    final base = Movement(
      id: 'x',
      kind: MovementKind.adjustment,
      amount: const Money(800, 'PEN'),
      categoryId: kNoCategoryId,
      date: DateTime(2026, 10, 18),
      createdAt: DateTime(2026, 10, 18),
      adjustmentMinor: -800,
    );
    expect(base.signedMinor, -800);
    expect(base.copyWith(kind: MovementKind.transfer).signedMinor, 0);
    expect(base.isExpense, isFalse);
  });

  group('campos de cuentas en Movement', () {
    final accountFull = Movement(
      id: 'm3',
      kind: MovementKind.transfer,
      amount: const Money(10000, 'PEN'),
      categoryId: kNoCategoryId,
      date: DateTime(2026, 10, 18),
      createdAt: DateTime(2026, 10, 18, 9),
      origin: MovementOrigin.statement,
      accountId: 'A',
      toAccountId: 'B',
      transferIncoming: true,
      receivedMinor: 2700,
      adjustmentMinor: -800,
      paidMinor: 0,
      needsReview: true,
      externalRef: 'ref-123',
    );

    test('sobreviven a JSON', () {
      final back = Movement.fromJson(accountFull.toJson());
      expect(back.toJson(), accountFull.toJson());
      expect(back.kind, MovementKind.transfer);
      expect(back.origin, MovementOrigin.statement);
      expect(back.accountId, 'A');
      expect(back.toAccountId, 'B');
      expect(back.transferIncoming, isTrue);
      expect(back.receivedMinor, 2700);
      expect(back.adjustmentMinor, -800);
      expect(back.paidMinor, 0);
      expect(back.needsReview, isTrue);
      expect(back.externalRef, 'ref-123');
    });

    test('copyWith los conserva (editar no saca un movimiento de su cuenta)', () {
      final edited = accountFull.copyWith(note: 'nota');
      expect(edited.note, 'nota');
      expect(edited.toJson()..remove('note'), accountFull.toJson()..remove('note'));
    });

    test('copyWith los cambia', () {
      final m = full.copyWith(
        accountId: 'A',
        toAccountId: 'B',
        transferIncoming: true,
        receivedMinor: 1,
        adjustmentMinor: 2,
        paidMinor: 3,
        needsReview: true,
        externalRef: 'r',
      );
      expect(m.accountId, 'A');
      expect(m.toAccountId, 'B');
      expect(m.transferIncoming, isTrue);
      expect(m.receivedMinor, 1);
      expect(m.adjustmentMinor, 2);
      expect(m.paidMinor, 3);
      expect(m.needsReview, isTrue);
      expect(m.externalRef, 'r');
    });

    test('un JSON antiguo se lee igual: sin cuenta y con todo por defecto', () {
      final m = Movement.fromJson({
        'id': 'viejo',
        'kind': 'expense',
        'amount': {'minor': 2990, 'currency': 'PEN'},
        'categoryId': 'food',
        'date': '2026-09-01T12:00:00.000',
        'title': 'Almuerzo',
        'note': '',
        'origin': 'googlePay',
        'subscriptionId': null,
        'provisional': false,
        'userEdited': false,
        'createdAt': '2026-09-01T12:00:00.000',
      });
      expect(m.kind, MovementKind.expense);
      expect(m.origin, MovementOrigin.googlePay);
      expect(m.amount, const Money(2990, 'PEN'));
      expect(m.accountId, isNull);
      expect(m.toAccountId, isNull);
      expect(m.transferIncoming, isFalse);
      expect(m.receivedMinor, isNull);
      expect(m.adjustmentMinor, isNull);
      expect(m.paidMinor, isNull);
      expect(m.needsReview, isFalse);
      expect(m.externalRef, isNull);
      expect(m.countsInWallet, isTrue);
    });

    test('todos los tipos y orígenes antiguos conservan su nombre guardado', () {
      expect(MovementKind.values.asNameMap().keys, containsAll(['expense', 'income', 'transfer', 'adjustment']));
      expect(
        MovementOrigin.values.asNameMap().keys,
        containsAll([
          'manual', 'subscription', 'initialBalance', 'applePay', 'ticket', 'split', 'googlePay',
          'settlement', 'capture', 'statement',
        ]),
      );
    });

    test('una transferencia o un ajuste sin categoría se leen sin romperse', () {
      final m = Movement.fromJson({
        'id': 't',
        'kind': 'transfer',
        'amount': {'minor': 100, 'currency': 'PEN'},
        'date': '2026-10-01T00:00:00.000',
      });
      expect(m.categoryId, kNoCategoryId);
    });
  });

  group('WalletAccount', () {
    final account = WalletAccount(
      id: 'bcp',
      name: 'BCP',
      type: AccountType.bank,
      currency: 'PEN',
      initialMinor: 150000,
      initialDate: DateTime(2026, 10, 1),
      lastDigits: '1234',
      isDefault: true,
      archived: true,
    );

    test('sobrevive a JSON con todos los campos', () {
      final back = WalletAccount.fromJson(account.toJson());
      expect(back.toJson(), account.toJson());
      expect(back.type, AccountType.bank);
      expect(back.lastDigits, '1234');
      expect(back.initialDate, DateTime(2026, 10, 1));
    });

    test('un tipo desconocido es "otra" y lo opcional tiene valor por defecto', () {
      final a = WalletAccount.fromJson({
        'id': 'x',
        'name': 'X',
        'type': 'cripto',
        'currency': 'PEN',
        'initialMinor': 0,
        'initialDate': '2026-10-01T00:00:00.000',
      });
      expect(a.type, AccountType.other);
      expect(a.isDefault, isFalse);
      expect(a.archived, isFalse);
      expect(a.lastDigits, isNull);
    });

    test('copyWith cambia lo pedido y conserva lo demás', () {
      final c = account.copyWith(name: 'BCP Soles', archived: false);
      expect(c.name, 'BCP Soles');
      expect(c.archived, isFalse);
      expect(c.id, 'bcp');
      expect(c.lastDigits, '1234');
      expect(c.initialMinor, 150000);
      expect(c.isDefault, isTrue);
    });
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
