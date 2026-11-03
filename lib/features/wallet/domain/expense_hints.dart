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

/// Primeras palabras demasiado comunes para identificar un comercio.
const _genericWords = {'plaza', 'tienda', 'santa', 'mercado', 'bodega', 'restaurante', 'grupo', 'casa'};

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
  final words = m.split(' ');

  // El gasto anterior que más palabras iniciales comparte con este comercio
  // (a igualdad, el más reciente). Una sola palabra en común solo cuenta si
  // es significativa: "La …" o "Plaza …" no bastan.
  Movement? best;
  var bestScore = 0;
  for (final x in history) {
    if (!x.isExpense ||
        x.origin == MovementOrigin.subscription ||
        x.origin == MovementOrigin.settlement ||
        !valid.contains(x.categoryId)) {
      continue;
    }
    final other = normalizeMerchant(x.title).split(' ');
    var score = 0;
    while (score < words.length && score < other.length && words[score] == other[score]) {
      score++;
    }
    final exact = score == words.length && score == other.length;
    if (exact) score += 100;
    final meaningful = score >= 2 || (score == 1 && words.first.length >= 4 && !_genericWords.contains(words.first));
    if (!meaningful) continue;
    if (score > bestScore || (score == bestScore && x.createdAt.isAfter(best!.createdAt))) {
      best = x;
      bestScore = score;
    }
  }
  if (best != null) return best.categoryId;

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
