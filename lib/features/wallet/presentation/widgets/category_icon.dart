import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/category.dart';

/// Iconos disponibles para categorías (nombre guardado → icono).
const kCategoryIcons = <String, IconData>{
  'utensils': LucideIcons.utensils,
  'shoppingBasket': LucideIcons.shoppingBasket,
  'car': LucideIcons.car,
  'house': LucideIcons.house,
  'zap': LucideIcons.zap,
  'heartPulse': LucideIcons.heartPulse,
  'popcorn': LucideIcons.popcorn,
  'shoppingBag': LucideIcons.shoppingBag,
  'graduationCap': LucideIcons.graduationCap,
  'repeat': LucideIcons.repeat,
  'ellipsis': LucideIcons.ellipsis,
  'briefcase': LucideIcons.briefcase,
  'laptop': LucideIcons.laptop,
  'store': LucideIcons.store,
  'arrowDownLeft': LucideIcons.arrowDownLeft,
  'coffee': LucideIcons.coffee,
  'plane': LucideIcons.plane,
  'gift': LucideIcons.gift,
  'dumbbell': LucideIcons.dumbbell,
  'pawPrint': LucideIcons.pawPrint,
  'baby': LucideIcons.baby,
  'shirt': LucideIcons.shirt,
  'smartphone': LucideIcons.smartphone,
  'fuel': LucideIcons.fuel,
  'piggyBank': LucideIcons.piggyBank,
  'circle': LucideIcons.circle,
};

IconData categoryIcon(String name) => kCategoryIcons[name] ?? LucideIcons.circle;

/// Círculo de color suave con el icono de la categoría.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.category, this.size = 40});

  final Category? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(category?.color ?? 0xFF8E8E93);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
      child: Icon(categoryIcon(category?.icon ?? 'circle'), size: size * 0.48, color: color),
    );
  }
}
