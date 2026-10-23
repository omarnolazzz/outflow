import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/friends/domain/balances.dart';
import 'package:outflow/features/friends/domain/shared_expense.dart';

SharedExpense exp({
  required String id,
  required String paidBy,
  required Map<String, int> shares,
  String currency = 'PEN',
  Map<String, Settlement> settled = const {},
}) =>
    SharedExpense(
      id: id,
      createdBy: paidBy,
      paidBy: paidBy,
      participants: shares.keys.toList(),
      people: {
        for (final u in shares.keys) u: Person(uid: u, name: 'Nombre $u', email: '$u@x.com'),
      },
      title: 'Cena',
      date: DateTime(2026, 10, 1),
      currency: currency,
      totalMinor: shares.values.fold(0, (s, v) => s + v),
      categoryId: 'food',
      mode: SplitMode.equal,
      shares: shares,
      settled: settled,
      updatedAt: DateTime(2026, 10, 1),
    );

Map<String, Balance> byFriend(List<Balance> l) => {for (final b in l) b.friendUid: b};

void main() {
  final pague = exp(id: '1', paidBy: 'me', shares: {'me': 3334, 'ana': 3333, 'javi': 3333});

  test('pagué yo: me deben', () {
    final b = byFriend(computeBalances([pague], 'me'));
    expect(b['ana']!.byCurrency, {'PEN': 3333});
    expect(b['javi']!.byCurrency, {'PEN': 3333});
  });

  test('ana pagó: le debo y se netea', () {
    final ana = exp(id: '2', paidBy: 'ana', shares: {'ana': 1500, 'me': 1500});
    final b = byFriend(computeBalances([pague, ana], 'me'));
    expect(b['ana']!.byCurrency, {'PEN': 3333 - 1500});
    final solo = byFriend(computeBalances([ana], 'me'));
    expect(solo['ana']!.byCurrency, {'PEN': -1500});
  });

  test('saldado no aparece', () {
    final s = exp(
      id: '3',
      paidBy: 'me',
      shares: {'me': 3334, 'ana': 3333, 'javi': 3333},
      settled: {'javi': Settlement(by: 'me', at: DateTime(2026, 10, 2))},
    );
    final b = byFriend(computeBalances([s], 'me'));
    expect(b.containsKey('javi'), isFalse);
    expect(b.containsKey('ana'), isTrue);
  });

  test('saldos netos a cero no aparecen', () {
    final a = exp(id: '4', paidBy: 'me', shares: {'me': 1000, 'ana': 1000});
    final b = exp(id: '5', paidBy: 'ana', shares: {'me': 1000, 'ana': 1000});
    expect(computeBalances([a, b], 'me'), isEmpty);
  });

  test('dos monedas', () {
    final usd = exp(id: '6', paidBy: 'me', currency: 'USD', shares: {'me': 500, 'ana': 500});
    final b = byFriend(computeBalances([pague, usd], 'me'));
    expect(b['ana']!.byCurrency, {'PEN': 3333, 'USD': 500});
  });

  test('totalsByCurrency', () {
    final ana = exp(id: '2', paidBy: 'ana', shares: {'ana': 9000, 'me': 9000});
    final t = totalsByCurrency(computeBalances([pague, ana], 'me'));
    expect(t.owedToMe, {'PEN': 3333});
    expect(t.iOwe, {'PEN': 9000 - 3333});
  });

  test('SharedExpense toJson/fromJson', () {
    final e = exp(id: '7', paidBy: 'me', shares: {'me': 3334, 'ana': 3333}, settled: {
      'ana': Settlement(by: 'me', at: DateTime(2026, 10, 2)),
    }).copyWith(items: [SplitItem(name: 'Pizza', amountMinor: 100, uids: ['me'])]);
    final r = SharedExpense.fromJson(e.toJson());
    expect(r.id, e.id);
    expect(r.paidBy, e.paidBy);
    expect(r.participants, e.participants);
    expect(r.people['ana']!.email, 'ana@x.com');
    expect(r.date, e.date);
    expect(r.currency, e.currency);
    expect(r.totalMinor, e.totalMinor);
    expect(r.mode, e.mode);
    expect(r.shares, e.shares);
    expect(r.items.single.name, 'Pizza');
    expect(r.settled['ana']!.by, 'me');
    expect(r.settled['ana']!.at, DateTime(2026, 10, 2));
    expect(r.updatedAt, e.updatedAt);
    expect(r.shareOf('zzz'), 0);
    expect(r.isSettled('ana'), isTrue);
    expect(r.debtors, ['ana']);
  });
}
