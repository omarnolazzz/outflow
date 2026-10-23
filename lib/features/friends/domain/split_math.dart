import '../../../core/domain/money.dart';
import '../../../core/utils/formatters.dart';
import 'shared_expense.dart';

/// Reparte [totalMinor] a partes iguales; los céntimos sobrantes van a los
/// primeros de la lista.
Map<String, int> splitEqually(int totalMinor, List<String> uids) {
  if (uids.isEmpty) return {};
  final base = totalMinor ~/ uids.length;
  final extra = totalMinor - base * uids.length;
  return {for (var i = 0; i < uids.length; i++) uids[i]: base + (i < extra ? 1 : 0)};
}

/// Cada producto se divide a partes iguales entre sus personas; si la suma de
/// productos difiere de [totalMinor] (propina, descuento), la diferencia se
/// reparte en proporción a lo ya asignado (mayor resto).
Map<String, int> splitByItems(List<SplitItem> items, int totalMinor) {
  final assigned = <String, int>{};
  for (final item in items) {
    if (item.uids.isEmpty) {
      throw ArgumentError('El producto "${item.name}" no tiene personas asignadas');
    }
    splitEqually(item.amountMinor, item.uids).forEach((u, v) => assigned[u] = (assigned[u] ?? 0) + v);
  }
  final sum = assigned.values.fold<int>(0, (s, v) => s + v);
  if (sum == totalMinor || assigned.isEmpty) return assigned;
  if (sum == 0) return splitEqually(totalMinor, assigned.keys.toList());

  final uids = assigned.keys.toList();
  final result = <String, int>{};
  final remainders = <String, int>{};
  for (final u in uids) {
    final scaled = assigned[u]! * totalMinor;
    result[u] = scaled ~/ sum;
    remainders[u] = scaled % sum;
  }
  var left = totalMinor - result.values.fold<int>(0, (s, v) => s + v);
  final order = [...uids]..sort((a, b) => remainders[b]!.compareTo(remainders[a]!));
  for (final u in order) {
    if (left <= 0) break;
    result[u] = result[u]! + 1;
    left--;
  }
  return result;
}

/// Null si las partes suman [totalMinor]; si no, un mensaje para el usuario.
String? validateShares(Map<String, int> shares, int totalMinor, {required String currency}) {
  final diff = totalMinor - shares.values.fold<int>(0, (s, v) => s + v);
  if (diff == 0) return null;
  final amount = Fmt.money(Money(diff.abs(), currency));
  return diff > 0 ? 'Faltan $amount por repartir' : 'Sobran $amount';
}
