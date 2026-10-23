import 'package:meta/meta.dart';

/// Persona que participa en un gasto compartido (copia embebida en el gasto).
@immutable
class Person {
  const Person({required this.uid, required this.name, required this.email, this.photoUrl});

  final String uid;
  final String name;
  final String email;
  final String? photoUrl;

  /// Primer nombre, o el nombre completo si solo hay una palabra.
  String get firstName {
    final t = name.trim();
    final i = t.indexOf(' ');
    return i < 0 ? t : t.substring(0, i);
  }

  /// Primer nombre; sin nombre, la parte local del correo; sin nada, "Amigo".
  String get shortName {
    final first = firstName;
    if (first.isNotEmpty) return first;
    final local = email.trim().split('@').first;
    return local.isEmpty ? 'Amigo' : local;
  }

  Map<String, Object?> toJson() => {'uid': uid, 'name': name, 'email': email, 'photoUrl': photoUrl};

  factory Person.fromJson(Map<String, Object?> json) => Person(
        uid: json['uid'] as String,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        photoUrl: json['photoUrl'] as String?,
      );
}

/// Cómo se reparte el gasto.
enum SplitMode { equal, amounts, items }

/// Producto de un reparto por ítems, compartido entre [uids].
@immutable
class SplitItem {
  const SplitItem({required this.name, required this.amountMinor, required this.uids});

  final String name;
  final int amountMinor;
  final List<String> uids;

  Map<String, Object?> toJson() => {'name': name, 'amountMinor': amountMinor, 'uids': uids};

  factory SplitItem.fromJson(Map<String, Object?> json) => SplitItem(
        name: json['name'] as String? ?? '',
        amountMinor: (json['amountMinor'] as num).toInt(),
        uids: ((json['uids'] as List?) ?? const []).cast<String>(),
      );
}

/// Marca de que un deudor ya pagó su parte.
@immutable
class Settlement {
  const Settlement({required this.by, required this.at});

  final String by;
  final DateTime at;

  Map<String, Object?> toJson() => {'by': by, 'at': at.toIso8601String()};

  factory Settlement.fromJson(Map<String, Object?> json) =>
      Settlement(by: json['by'] as String, at: DateTime.parse(json['at'] as String));
}

/// Gasto pagado por una persona y repartido entre varias.
@immutable
class SharedExpense {
  const SharedExpense({
    required this.id,
    required this.createdBy,
    required this.paidBy,
    required this.participants,
    required this.people,
    required this.title,
    required this.date,
    required this.currency,
    required this.totalMinor,
    required this.categoryId,
    required this.mode,
    required this.shares,
    required this.updatedAt,
    this.items = const [],
    this.settled = const {},
  });

  final String id;
  final String createdBy;
  final String paidBy;
  final List<String> participants;
  final Map<String, Person> people;
  final String title;
  final DateTime date;
  final String currency;
  final int totalMinor;
  final String categoryId;
  final SplitMode mode;

  /// Parte de cada participante en unidades menores.
  final Map<String, int> shares;
  final List<SplitItem> items;

  /// Deudas saldadas, por uid del deudor.
  final Map<String, Settlement> settled;
  final DateTime updatedAt;

  /// Parte de [uid] (0 si no participa).
  int shareOf(String uid) => shares[uid] ?? 0;

  bool isSettled(String debtorUid) => settled.containsKey(debtorUid);

  /// Participantes distintos de quien pagó con una parte mayor que cero.
  Iterable<String> get debtors => participants.where((u) => u != paidBy && shareOf(u) > 0);

  SharedExpense copyWith({
    String? paidBy,
    List<String>? participants,
    Map<String, Person>? people,
    String? title,
    DateTime? date,
    String? currency,
    int? totalMinor,
    String? categoryId,
    SplitMode? mode,
    Map<String, int>? shares,
    List<SplitItem>? items,
    Map<String, Settlement>? settled,
    DateTime? updatedAt,
  }) =>
      SharedExpense(
        id: id,
        createdBy: createdBy,
        paidBy: paidBy ?? this.paidBy,
        participants: participants ?? this.participants,
        people: people ?? this.people,
        title: title ?? this.title,
        date: date ?? this.date,
        currency: currency ?? this.currency,
        totalMinor: totalMinor ?? this.totalMinor,
        categoryId: categoryId ?? this.categoryId,
        mode: mode ?? this.mode,
        shares: shares ?? this.shares,
        items: items ?? this.items,
        settled: settled ?? this.settled,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'createdBy': createdBy,
        'paidBy': paidBy,
        'participants': participants,
        'people': people.map((k, v) => MapEntry(k, v.toJson())),
        'title': title,
        'date': date.toIso8601String(),
        'currency': currency,
        'totalMinor': totalMinor,
        'categoryId': categoryId,
        'mode': mode.name,
        'shares': shares,
        'items': items.map((i) => i.toJson()).toList(),
        'settled': settled.map((k, v) => MapEntry(k, v.toJson())),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SharedExpense.fromJson(Map<String, Object?> json) {
    final date = DateTime.parse(json['date'] as String);
    final updated = json['updatedAt'] as String?;
    Map<String, Object?> asMap(Object? o) => (o as Map).cast<String, Object?>();
    return SharedExpense(
      id: json['id'] as String,
      createdBy: json['createdBy'] as String,
      paidBy: json['paidBy'] as String,
      participants: ((json['participants'] as List?) ?? const []).cast<String>(),
      people: {
        for (final e in asMap(json['people'] ?? const {}).entries) e.key: Person.fromJson(asMap(e.value)),
      },
      title: json['title'] as String? ?? '',
      date: date,
      currency: json['currency'] as String,
      totalMinor: (json['totalMinor'] as num).toInt(),
      categoryId: json['categoryId'] as String? ?? '',
      mode: SplitMode.values.asNameMap()[json['mode']] ?? SplitMode.equal,
      shares: {
        for (final e in asMap(json['shares'] ?? const {}).entries) e.key: (e.value as num).toInt(),
      },
      items: [
        for (final i in (json['items'] as List?) ?? const []) SplitItem.fromJson(asMap(i)),
      ],
      settled: {
        for (final e in asMap(json['settled'] ?? const {}).entries) e.key: Settlement.fromJson(asMap(e.value)),
      },
      updatedAt: updated == null ? date : DateTime.parse(updated),
    );
  }
}
