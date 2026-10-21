import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/core/widgets/amount_keypad.dart';

void main() {
  test('los dígitos son enteros hasta pulsar la coma; máximo 2 decimales', () {
    final a = AmountInput()
      ..digit(1)
      ..digit(2)
      ..digit(3);
    expect(a.minor, 12300);
    a
      ..decimalPoint()
      ..digit(4)
      ..digit(5)
      ..digit(6);
    expect(a.minor, 12345, reason: 'el tercer decimal se ignora');
    a.backspace();
    expect(a.minor, 12340);
    a
      ..backspace()
      ..backspace()
      ..backspace();
    expect(a.minor, 1200);
    expect(AmountInput().display('PEN'), 'S/ 0');
  });

  test('máximo 9 dígitos enteros', () {
    final a = AmountInput();
    for (var i = 0; i < 12; i++) {
      a.digit(9);
    }
    expect(a.minor, 99999999900);
  });

  test('setMinor muestra los decimales y se puede seguir editando', () {
    final a = AmountInput()..setMinor(2990);
    expect(a.minor, 2990);
    expect(a.display('PEN'), 'S/ 29.90');
    a.backspace();
    expect(a.display('PEN'), 'S/ 29.9');
    a.backspace();
    expect(a.minor, 2900);
  });

  test('un cero a la izquierda no se acumula', () {
    final a = AmountInput()
      ..digit(0)
      ..digit(0)
      ..digit(5);
    expect(a.minor, 500);
    expect(a.display('PEN'), 'S/ 5');
  });
}
