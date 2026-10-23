import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/friends/domain/shared_expense.dart';
import 'package:outflow/features/friends/domain/split_math.dart';

void main() {
  test('splitEqually reparte los céntimos sobrantes a los primeros', () {
    expect(splitEqually(10000, ['a', 'b', 'c']), {'a': 3334, 'b': 3333, 'c': 3333});
    expect(splitEqually(100, ['a']), {'a': 100});
  });

  group('splitByItems', () {
    final pizza = SplitItem(name: 'Pizza', amountMinor: 6000, uids: ['a', 'b']);
    final cerveza = SplitItem(name: 'Cerveza', amountMinor: 2000, uids: ['b']);

    test('suma exacta', () {
      expect(splitByItems([pizza, cerveza], 8000), {'a': 3000, 'b': 5000});
    });

    test('propina: la diferencia se reparte en proporción', () {
      final r = splitByItems([pizza, cerveza], 8800);
      expect(r, {'a': 3300, 'b': 5500});
      expect(r.values.fold<int>(0, (s, v) => s + v), 8800);
    });

    test('producto sin personas lanza ArgumentError', () {
      final vacio = SplitItem(name: 'X', amountMinor: 100, uids: []);
      expect(() => splitByItems([vacio], 100), throwsArgumentError);
    });
  });

  group('validateShares', () {
    test('faltan', () {
      expect(validateShares({'a': 5000, 'b': 4600}, 10000, currency: 'PEN'), contains('Faltan'));
    });
    test('sobran', () {
      expect(validateShares({'a': 5000, 'b': 5400}, 10000, currency: 'PEN'), contains('Sobran'));
    });
    test('exacto', () {
      expect(validateShares({'a': 5000, 'b': 5000}, 10000, currency: 'PEN'), isNull);
    });
  });
}
