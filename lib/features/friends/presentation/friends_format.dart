import 'package:flutter/material.dart';

import '../../../core/domain/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../domain/balances.dart';
import '../domain/shared_expense.dart';

/// "S/ 25.00" o, con varias monedas, "S/ 25.00 + US$ 3.00".
String moneyList(Map<String, int> byCurrency) =>
    byCurrency.entries.map((e) => Fmt.money(Money(e.value.abs(), e.key))).join(' + ');

/// Lo que te deben / debes con un amigo, por moneda.
({Map<String, int> owed, Map<String, int> owe}) splitBalance(Balance? b) {
  final owed = <String, int>{};
  final owe = <String, int>{};
  b?.byCurrency.forEach((c, v) {
    if (v > 0) owed[c] = v;
    if (v < 0) owe[c] = -v;
  });
  return (owed: owed, owe: owe);
}

/// "Te debe S/ 25", "Le debes S/ 12" o "Al día".
String balanceLabel(Balance? b) {
  final s = splitBalance(b);
  final parts = [
    if (s.owed.isNotEmpty) 'Te debe ${moneyList(s.owed)}',
    if (s.owe.isNotEmpty) 'Le debes ${moneyList(s.owe)}',
  ];
  return parts.isEmpty ? 'Al día' : parts.join(' · ');
}

/// "Te deben S/ 75 · Debes S/ 12"; null si no hay saldos.
String? totalsLabel(List<Balance> balances) {
  final t = totalsByCurrency(balances);
  final parts = [
    if (t.owedToMe.isNotEmpty) 'Te deben ${moneyList(t.owedToMe)}',
    if (t.iOwe.isNotEmpty) 'Debes ${moneyList(t.iOwe)}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Lanza una escritura de Firestore sin esperarla: sin conexión nunca termina
/// y los streams ya reflejan el cambio desde la caché local. Solo avisa si falla.
void fireWrite(BuildContext context, Future<void> write, {String message = 'No se pudo completar. Inténtalo de nuevo.'}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  write.then<void>((_) {}, onError: (Object e) {
    debugPrint('Escritura de Amigos fallida: $e');
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  });
}

/// Círculo con la inicial de una persona.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar(this.person, {super.key, this.size = 40});

  final Person person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final name = person.name.trim().isEmpty ? person.email : person.name.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w600, color: AppColors.accent),
      ),
    );
  }
}
