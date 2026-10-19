import 'package:meta/meta.dart';

import '../../../../core/domain/billing_cycle.dart';
import '../../../../core/domain/money.dart';

enum SpendCategory {
  streaming('Streaming'),
  music('Música'),
  mobile('Operadores móviles'),
  internet('Internet y hogar'),
  software('Software'),
  cloud('Nube y almacenamiento'),
  gaming('Juegos'),
  news('Noticias y lectura'),
  fitness('Salud y fitness'),
  education('Educación'),
  shopping('Compras y membresías'),
  other('Otros');

  const SpendCategory(this.label);
  final String label;
}

enum LogoKind {
  /// Emoji plano (p. ej. "🎬").
  emoji,

  /// Icono lineal del registro interno (clave estable, p. ej. "tv").
  icon,

  /// Imagen guardada en el almacenamiento local del dispositivo.
  file,

  /// Iniciales generadas a partir del nombre (fallback).
  monogram,
}

/// Logotipo de un comercio. Se guarda como dato (no como IconData) para que
/// la capa de dominio no dependa de Flutter y la persistencia sea estable.
@immutable
class MerchantLogo {
  const MerchantLogo._(this.kind, this.value);

  const MerchantLogo.emoji(String emoji) : this._(LogoKind.emoji, emoji);
  const MerchantLogo.icon(String iconKey) : this._(LogoKind.icon, iconKey);
  const MerchantLogo.file(String path) : this._(LogoKind.file, path);
  const MerchantLogo.monogram() : this._(LogoKind.monogram, '');

  final LogoKind kind;
  final String value;

  Map<String, Object?> toJson() => {'kind': kind.name, 'value': value};

  factory MerchantLogo.fromJson(Map<String, Object?> json) => MerchantLogo._(
        LogoKind.values.byName(json['kind'] as String),
        json['value'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is MerchantLogo && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// Reglas de facturación por defecto de un comercio. Se usan para precargar
/// el formulario al crear una suscripción de ese comercio.
@immutable
class BillingDefaults {
  const BillingDefaults({
    this.cycle = const BillingCycle.monthly(),
    this.price,
    this.cancellationWindowDays,
  });

  final BillingCycle cycle;
  final Money? price;

  /// Días que el comercio concede para cancelar tras el cobro automático.
  final int? cancellationWindowDays;

  Map<String, Object?> toJson() => {
        'cycle': cycle.toJson(),
        'price': price?.toJson(),
        'cancellationWindowDays': cancellationWindowDays,
      };

  factory BillingDefaults.fromJson(Map<String, Object?> json) => BillingDefaults(
        cycle: BillingCycle.fromJson((json['cycle'] as Map).cast()),
        price: json['price'] == null ? null : Money.fromJson((json['price'] as Map).cast()),
        cancellationWindowDays: (json['cancellationWindowDays'] as num?)?.toInt(),
      );
}

@immutable
class Merchant {
  const Merchant({
    required this.id,
    required this.name,
    required this.category,
    required this.logo,
    this.billing = const BillingDefaults(),
    this.isCustom = false,
  });

  final String id;
  final String name;
  final SpendCategory category;
  final MerchantLogo logo;
  final BillingDefaults billing;

  /// true si lo creó el usuario (editable/eliminable); false si viene del catálogo.
  final bool isCustom;

  Merchant copyWith({
    String? name,
    SpendCategory? category,
    MerchantLogo? logo,
    BillingDefaults? billing,
  }) =>
      Merchant(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        logo: logo ?? this.logo,
        billing: billing ?? this.billing,
        isCustom: isCustom,
      );
}
