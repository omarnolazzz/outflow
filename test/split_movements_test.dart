import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/features/friends/domain/shared_expense.dart';
import 'package:outflow/features/friends/domain/split_movements.dart';
import 'package:outflow/features/wallet/domain/movement.dart';

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
  }) => reconcileSplitMovements(
    snapshot: ExpensesSnapshot(es, fromCache: fromCache),
    existing: existing,
    myUid: 'me',
    categoryIds: cats,
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
}
