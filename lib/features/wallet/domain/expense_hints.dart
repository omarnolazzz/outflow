import 'category.dart';
import 'movement.dart';

/// Comercio comparable: minúsculas, sin acentos y sin espacios de sobra.
String normalizeMerchant(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñ';
  const to = 'aaaaeeeeiiiioooouuuun';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i == -1 ? ch : to[i]);
  }
  return b.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Palabras clave → categoría, para comercios nunca vistos.
const kCategoryKeywords = <String, List<String>>{
  'groceries': ['supermercado', 'plaza vea', 'tottus', 'wong', 'metro', 'makro', 'vivanda', 'mass', 'tambo', 'oxxo'],
  'transport': ['uber', 'cabify', 'didi', 'indriver', 'taxi', 'grifo', 'primax', 'repsol', 'pecsa', 'petroperu', 'peaje'],
  'food': ['starbucks', 'kfc', 'bembos', 'mcdonald', 'pizza', 'restaurant', 'cafe', 'rappi', 'pedidosya', 'burger', 'chifa', 'polleria'],
  'health': ['farmacia', 'inkafarma', 'mifarma', 'boticas', 'clinica', 'hospital'],
  'leisure': ['cine', 'cineplanet', 'cinemark', 'teleticket', 'joinnus'],
  'shopping': ['falabella', 'ripley', 'oechsle', 'amazon', 'aliexpress', 'shein', 'zara', 'h&m'],
  'utilities': ['luz del sur', 'enel', 'sedapal', 'calidda', 'movistar', 'claro', 'entel', 'bitel'],
};

/// Categoría probable para un gasto en [merchant]: la usada la última vez con
/// ese comercio; si no, por palabras clave; si no, null.
String? suggestCategory({
  required String merchant,
  required List<Movement> history,
  required List<Category> categories,
}) {
  final m = normalizeMerchant(merchant);
  if (m.isEmpty) return null;
  final valid = {for (final c in categories) c.id};
  final firstWord = m.split(' ').first;

  final previous = history
      .where((x) =>
          x.isExpense &&
          x.origin != MovementOrigin.subscription &&
          valid.contains(x.categoryId) &&
          normalizeMerchant(x.title).split(' ').first == firstWord)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  if (previous.isNotEmpty) return previous.first.categoryId;

  for (final e in kCategoryKeywords.entries) {
    if (valid.contains(e.key) && e.value.any(m.contains)) return e.key;
  }
  return null;
}

/// Gasto igual (importe y comercio) registrado hace muy poco: el atajo se
/// ejecutó dos veces o el pago ya se apuntó a mano.
Movement? findRecentDuplicate({
  required List<Movement> movements,
  required int amountMinor,
  required String merchant,
  required DateTime now,
  Duration window = const Duration(minutes: 2),
}) {
  final m = normalizeMerchant(merchant);
  for (final x in movements) {
    if (!x.isExpense || x.amount.minor != amountMinor) continue;
    if (normalizeMerchant(x.title) != m) continue;
    final age = now.difference(x.createdAt).abs();
    if (age <= window) return x;
  }
  return null;
}
