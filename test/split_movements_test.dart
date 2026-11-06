import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/friends/domain/shared_expense.dart';
import 'package:outflow/features/friends/domain/split_movements.dart';
import 'package:outflow/features/wallet/domain/account_balances.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';

void main() {
  const me = Person(uid: 'me', name: 'Gabriel Nolazco', email: 'g@x.com');
  const ana = Person(uid: 'ana', name: 'Ana Ruiz', email: 'a@x.com');
  const javi = Person(uid: 'javi', name: 'Javi', email: 'j@x.com');
  final cats = {'food', 'expense_other'};

  SharedExpense expense({
    String title = 'Cena',
    String categoryId = 'food',
    Map<String, int>? shares,
  }) => SharedExpense(
    id: 'e1',
    createdBy: 'ana',
    paidBy: 'ana',
    participants: const ['me', 'ana', 'javi'],
    people: const {'me': me, 'ana': ana, 'javi': javi},
    title: title,
    date: DateTime(2026, 10, 20),
    currency: 'PEN',
    totalMinor: 10000,
    categoryId: categoryId,
    mode: SplitMode.equal,
    shares: shares ?? const {'me': 3333, 'ana': 3334, 'javi': 3333},
    updatedAt: DateTime(2026, 10, 20),
  );

  ({List<Movement> upsert, List<String> delete}) run(
    List<SharedExpense> es,
    List<Movement> existing, {
    bool fromCache = false,
    Map<String, String> accounts = const {},
    DateTime? now,
  }) => reconcileSplitMovements(
    snapshot: ExpensesSnapshot(es, fromCache: fromCache),
    existing: existing,
    myUid: 'me',
    categoryIds: cats,
    splitAccountIds: accounts,
    now: now ?? DateTime(2026, 10, 25),
  );

  test('gasto nuevo crea tu parte', () {
    final r = run([expense()], const []);
    expect(r.delete, isEmpty);
    final m = r.upsert.single;
    expect(m.id, 'split:e1');
    expect(splitMovementId('e1'), 'split:e1');
    expect(m.kind, MovementKind.expense);
    expect(m.origin, MovementOrigin.split);
    expect(m.amount, const Money(3333, 'PEN'));
    expect(m.title, 'Cena');
    expect(m.date, DateTime(2026, 10, 20));
    expect(m.categoryId, 'food');
    expect(m.note, startsWith('Dividido con Ana, Javi · total '));
  });

  test('conciliar no le quita a tu parte su cuenta ni lo que salió de verdad', () {
    final current = run([expense().copyWith(paidBy: 'me')], const []).upsert.single.copyWith(
          accountId: 'A',
          paidMinor: 10000,
          needsReview: true,
          externalRef: 'r',
          pairedCaptureId: 'capture:x',
        );
    expect(run([expense().copyWith(paidBy: 'me')], [current]).upsert, isEmpty, reason: 'sin cambios: no reescribe');

    final changed = run([expense(title: 'Cena de grupo').copyWith(paidBy: 'me')], [current]).upsert.single;
    expect(changed.title, 'Cena de grupo');
    expect(changed.accountId, 'A');
    expect(changed.paidMinor, 10000);
    expect(changed.needsReview, isTrue);
    expect(changed.externalRef, 'r');
    expect(changed.pairedCaptureId, 'capture:x');
  });

  test('un nombre vacío usa la parte local del correo, o "Amigo"', () {
    final e = expense().copyWith(people: {
      'me': me,
      'ana': const Person(uid: 'ana', name: '  ', email: 'ana.ruiz@x.com'),
      'javi': const Person(uid: 'javi', name: '', email: ''),
    });
    final m = run([e], const []).upsert.single;
    expect(m.note, startsWith('Dividido con ana.ruiz, Amigo · total '));
  });

  test('categoría desconocida cae en Otros', () {
    final r = run([expense(categoryId: 'raro')], const []);
    expect(r.upsert.single.categoryId, 'expense_other');
  });

  test('segunda pasada no cambia nada', () {
    final first = run([expense()], const []).upsert.single;
    final r = run([expense()], [first]);
    expect(r.upsert, isEmpty);
    expect(r.delete, isEmpty);
  });

  test('cambia el título y conserva la categoría elegida por el usuario', () {
    final first = run([
      expense(),
    ], const []).upsert.single.copyWith(categoryId: 'expense_other');
    final r = run([expense(title: 'Cena larga')], [first]);
    expect(r.upsert.single.title, 'Cena larga');
    expect(r.upsert.single.categoryId, 'expense_other');
  });

  test('gasto ausente: con caché no borra, con servidor sí', () {
    final first = run([expense()], const []).upsert.single;
    expect(run(const [], [first], fromCache: true).delete, isEmpty);
    expect(run(const [], [first]).delete, ['split:e1']);
  });

  test('parte 0 borra el movimiento (solo con servidor)', () {
    final first = run([expense()], const []).upsert.single;
    final zero = expense(shares: const {'ana': 10000});
    expect(run([zero], [first]).delete, ['split:e1']);
    expect(run([zero], [first], fromCache: true).delete, isEmpty);
    expect(run([zero], const []).upsert, isEmpty);
  });

  test('movimientos manuales nunca se tocan', () {
    final manual = Movement(
      id: 'x',
      kind: MovementKind.expense,
      amount: const Money(100, 'PEN'),
      categoryId: 'food',
      date: DateTime(2026, 10, 1),
      createdAt: DateTime(2026, 10, 1),
    );
    final r = run(const [], [manual]);
    expect(r.delete, isEmpty);
    expect(r.upsert, isEmpty);
  });

  final today = DateTime(2026, 10, 25, 12);
  final account = WalletAccount(
    id: 'A',
    name: 'Banco',
    type: AccountType.bank,
    currency: 'PEN',
    initialMinor: 100000,
    initialDate: DateTime(2026, 1, 1),
    isDefault: true,
  );

  group('dinero real', () {
    /// Pagaste tú 10000 entre 4: tu parte es 2500.
    SharedExpense mine({String paidBy = 'me', DateTime? date}) => SharedExpense(
      id: 'e1',
      createdBy: 'me',
      paidBy: paidBy,
      participants: const ['me', 'ana', 'javi', 'bea'],
      people: const {'me': me, 'ana': ana, 'javi': javi, 'bea': Person(uid: 'bea', name: 'Bea', email: 'b@x.com')},
      title: 'Cena',
      date: date ?? DateTime(2026, 10, 20),
      currency: 'PEN',
      totalMinor: 10000,
      categoryId: 'food',
      mode: SplitMode.equal,
      shares: const {'me': 2500, 'ana': 2500, 'javi': 2500, 'bea': 2500},
      updatedAt: DateTime(2026, 10, 20),
    );

    test('pagaste tú: el Resumen cuenta tu parte y la cuenta pierde todo lo que salió', () {
      final m = run([mine()], const [], accounts: {'e1': 'A'}, now: today).upsert.single;
      expect(m.amount.minor, 2500);
      expect(m.countsInWallet, isTrue);
      expect(m.paidMinor, 10000);
      expect(m.accountId, 'A');
      expect(computeBalances([account], [m])['A'], 100000 - 10000);
    });

    test('pagó un amigo: el Resumen cuenta tu parte y la cuenta no se mueve', () {
      final m = run([mine(paidBy: 'ana')], const [], accounts: {'e1': 'A'}, now: today).upsert.single;
      expect(m.amount.minor, 2500);
      expect(m.paidMinor, 0);
      expect(computeBalances([account], [m])['A'], 100000);
    });

    test('sin cuenta guardada el gasto va a la cuenta por defecto', () {
      final m = run([mine()], const [], now: today).upsert.single;
      expect(m.accountId, isNull);
      expect(m.paidMinor, 10000);
    });

    test('un split antiguo (sin paidMinor) sigue moviendo solo tu parte', () {
      final old = run([mine()], const [], now: today).upsert.single;
      final legacy = Movement(
        id: old.id,
        kind: old.kind,
        amount: old.amount,
        categoryId: old.categoryId,
        date: old.date,
        createdAt: old.createdAt,
        title: old.title,
        note: old.note,
        origin: MovementOrigin.split,
      );
      final r = run([mine()], [legacy], accounts: {'e1': 'A'}, now: today);
      expect(r.upsert, isEmpty, reason: 'no se reescribe ni se le añade paidMinor');
      expect(computeBalances([account], [legacy])['A'], 100000 - 2500);
    });

    test('al actualizar conserva la cuenta y recalcula paidMinor solo si ya lo tenía', () {
      final first = run([mine()], const [], accounts: {'e1': 'A'}, now: today).upsert.single;
      final bigger = mine().copyWith(totalMinor: 12000, title: 'Cena grande');
      final changed = run([bigger], [first], accounts: {'e1': 'B'}, now: today).upsert.single;
      expect(changed.accountId, 'A', reason: 'la cuenta no cambia sola');
      expect(changed.paidMinor, 12000);
      expect(changed.createdAt, first.createdAt);
      // Si ahora paga otro, ya no sale nada de tu cuenta.
      final other = run([mine(paidBy: 'ana')], [first], accounts: {'e1': 'A'}, now: today).upsert.single;
      expect(other.paidMinor, 0);
    });

    test('borrar el gasto compartido quita su movimiento', () {
      final m = run([mine()], const [], now: today).upsert.single;
      expect(run(const [], [m], now: today).delete, ['split:e1']);
    });

    test('un split con fecha anterior a un ajuste que llega después no mueve la cuenta', () {
      final adjustment = makeAdjustment(account: account, currentMinor: 100000, realMinor: 90000, now: today)!;
      final late = run([mine(date: DateTime(2026, 10, 18))], const [], accounts: {'e1': 'A'}, now: today.add(const Duration(minutes: 1)))
          .upsert
          .single;
      expect(late.createdAt, today.add(const Duration(minutes: 1)), reason: 'createdAt es cuándo llegó, no la fecha del gasto');
      expect(computeBalances([account], [adjustment, late])['A'], 90000);
      // Uno posterior al ajuste sí lo baja.
      final after = run(
        [mine(date: today.add(const Duration(hours: 1)))],
        const [],
        accounts: {'e1': 'A'},
        now: today.add(const Duration(hours: 1)),
      ).upsert.single;
      expect(computeBalances([account], [adjustment, after])['A'], 80000);
    });
  });

  group('saldar', () {
    SharedExpense shared({String paidBy = 'ana', Map<String, Settlement> settled = const {}}) => expense().copyWith(
      paidBy: paidBy,
      shares: const {'me': 2500, 'ana': 2500, 'javi': 5000},
      settled: settled,
    );

    test('tu deuda de 2500 con cuenta: sale de la cuenta y el Resumen no cambia', () {
      final s = makeSettlementMovement(e: shared(), debtor: 'me', me: 'me', accountId: 'A', now: today)!;
      expect(s.id, 'settle:e1:me');
      expect(s.kind, MovementKind.adjustment);
      expect(s.origin, MovementOrigin.settlement);
      expect(s.adjustmentMinor, -2500);
      expect(s.accountId, 'A');
      expect(s.createdAt, today);
      expect(s.date, today);
      expect(s.countsInWallet, isFalse);
      expect(computeBalances([account], [s])['A'], 100000 - 2500);
    });

    test('un amigo te paga: entra su parte', () {
      final s = makeSettlementMovement(e: shared(paidBy: 'me'), debtor: 'javi', me: 'me', accountId: 'A', now: today)!;
      expect(s.id, 'settle:e1:javi');
      expect(s.adjustmentMinor, 5000);
      expect(computeBalances([account], [s])['A'], 105000);
    });

    test('sin cuenta (Ninguna) o sin que intervengas no hay movimiento', () {
      expect(makeSettlementMovement(e: shared(), debtor: 'me', me: 'me', accountId: null, now: today), isNull);
      // Ana pagó y Javi le salda: tú no intervienes.
      expect(makeSettlementMovement(e: shared(), debtor: 'javi', me: 'me', accountId: 'A', now: today), isNull);
    });

    test('un saldado no es punto de control: un gasto con fecha anterior apuntado después sí cuenta', () {
      final s = makeSettlementMovement(e: shared(), debtor: 'me', me: 'me', accountId: 'A', now: today)!;
      final expenseLater = Movement(
        id: 'x',
        kind: MovementKind.expense,
        amount: const Money(1000, 'PEN'),
        categoryId: 'food',
        date: DateTime(2026, 10, 20),
        createdAt: today.add(const Duration(minutes: 5)),
        accountId: 'A',
      );
      expect(computeBalances([account], [s, expenseLater])['A'], 100000 - 2500 - 1000);
    });

    test('si el saldado ya no existe en el servidor se borra su movimiento (no con caché)', () {
      final s = makeSettlementMovement(e: shared(), debtor: 'me', me: 'me', accountId: 'A', now: today)!;
      final settled = shared(settled: {'me': Settlement(by: 'me', at: today)});
      expect(run([settled], [s]).delete, isEmpty, reason: 'sigue saldado');
      expect(run([shared()], [s]).delete, ['settle:e1:me'], reason: 'ya no está saldado');
      expect(run([shared()], [s], fromCache: true).delete, isEmpty);
      expect(run(const [], [s]).delete, ['settle:e1:me'], reason: 'gasto borrado');
      expect(run(const [], [s], fromCache: true).delete, isEmpty);
    });
  });
}
