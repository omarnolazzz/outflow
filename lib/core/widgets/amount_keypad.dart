import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'pressable.dart';

/// Estado del importe que se teclea: parte entera (máx. 9 dígitos) y hasta 2
/// decimales tras pulsar la coma. Trabaja en unidades menores (céntimos).
class AmountInput extends ChangeNotifier {
  static const _maxInt = 9;

  String _int = '';
  String? _dec;

  int get minor => (int.tryParse(_int) ?? 0) * 100 + int.parse((_dec ?? '').padRight(2, '0'));

  bool get isEmpty => _int.isEmpty && _dec == null;

  void digit(int d) {
    assert(d >= 0 && d <= 9);
    if (_dec != null) {
      if (_dec!.length >= 2) return;
      _dec = '$_dec$d';
    } else {
      if (_int.length >= _maxInt) return;
      if (_int == '0') _int = '';
      if (_int.isEmpty && d == 0) {
        _int = '0';
      } else {
        _int = '$_int$d';
      }
    }
    notifyListeners();
  }

  void decimalPoint() {
    if (_dec != null) return;
    _dec = '';
    notifyListeners();
  }

  void backspace() {
    if (_dec != null) {
      _dec = _dec!.isEmpty ? null : _dec!.substring(0, _dec!.length - 1);
    } else if (_int.isNotEmpty) {
      _int = _int.substring(0, _int.length - 1);
    } else {
      return;
    }
    notifyListeners();
  }

  void setMinor(int value) {
    final whole = value ~/ 100;
    final cents = value % 100;
    _int = whole == 0 ? '' : '$whole';
    _dec = cents == 0 ? null : cents.toString().padLeft(2, '0');
    notifyListeners();
  }

  /// Tal como se teclea: "S/ 1,240", "S/ 29.9" (con la coma pendiente, "S/ 29.").
  String display(String currency) {
    final whole = NumberFormat.decimalPattern(Fmt.locale).format(int.tryParse(_int) ?? 0);
    final dec = _dec == null ? '' : '${Fmt.decimalSeparator}$_dec';
    return '${Fmt.symbol(currency)} $whole$dec';
  }
}

/// Teclado numérico propio (sin teclado del sistema: nada salta de sitio).
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.input});

  final AmountInput input;

  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, VoidCallback onTap, String label) => Expanded(
          child: SizedBox(
            height: 56,
            child: Pressable(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              scale: 0.9,
              borderRadius: BorderRadius.circular(16),
              semanticLabel: label,
              child: Center(child: child),
            ),
          ),
        );

    Widget digit(int d) => key(
          Text(
            '$d',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: AppColors.ink),
          ),
          () => input.digit(d),
          '$d',
        );

    Widget row(List<Widget> keys) => Row(children: keys);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row([digit(1), digit(2), digit(3)]),
        row([digit(4), digit(5), digit(6)]),
        row([digit(7), digit(8), digit(9)]),
        row([
          key(
            Text(
              Fmt.decimalSeparator,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: AppColors.ink),
            ),
            input.decimalPoint,
            'Decimales',
          ),
          digit(0),
          key(const Icon(LucideIcons.delete, size: 24, color: AppColors.inkSecondary), input.backspace, 'Borrar'),
        ]),
      ],
    );
  }
}
