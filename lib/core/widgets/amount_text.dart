import 'package:flutter/widgets.dart';

import '../domain/money.dart';
import '../motion/motion_widgets.dart';
import '../theme/app_typography.dart';

/// Importe que cuenta hasta su valor al aparecer y al cambiar.
class AmountText extends StatelessWidget {
  const AmountText(this.money, {super.key, this.style = AppType.amount});

  final Money money;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => CountUp.money(money, style: style);
}
