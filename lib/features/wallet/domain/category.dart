import 'package:meta/meta.dart';

import 'movement.dart';

/// Categoría donde caen los cobros de suscripciones (no se borra ni se elige a mano).
const kSubscriptionsCategoryId = 'subscriptions';

@immutable
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.kind,
    required this.icon,
    required this.color,
    this.reserved = false,
  });

  final String id;
  final String name;
  final MovementKind kind;

  /// Nombre del icono (la capa de presentación lo traduce a un IconData).
  final String icon;

  /// Color suave ARGB.
  final int color;

  /// Gestionada por la app: no aparece al registrar a mano ni se puede borrar.
  final bool reserved;

  Category copyWith({String? name, String? icon, int? color}) => Category(
        id: id,
        name: name ?? this.name,
        kind: kind,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        reserved: reserved,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'icon': icon,
        'color': color,
        'reserved': reserved,
      };

  factory Category.fromJson(Map<String, Object?> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: MovementKind.values.byName(json['kind'] as String),
        icon: json['icon'] as String? ?? 'circle',
        color: (json['color'] as num?)?.toInt() ?? 0xFF8E8E93,
        reserved: json['reserved'] as bool? ?? false,
      );
}
