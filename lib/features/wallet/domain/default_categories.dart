import 'category.dart';
import 'movement.dart';

/// Ingreso genérico (saldo inicial, sobrantes).
const kOtherIncomeCategoryId = 'income_other';

/// Categorías con las que empieza la app (editables en Ajustes).
List<Category> defaultCategories() => const [
      Category(id: 'food', name: 'Comida', kind: MovementKind.expense, icon: 'utensils', color: 0xFFFF9F0A),
      Category(id: 'groceries', name: 'Supermercado', kind: MovementKind.expense, icon: 'shoppingBasket', color: 0xFF34C759),
      Category(id: 'transport', name: 'Transporte', kind: MovementKind.expense, icon: 'car', color: 0xFF0A84FF),
      Category(id: 'home', name: 'Hogar', kind: MovementKind.expense, icon: 'house', color: 0xFFAC8E68),
      Category(id: 'utilities', name: 'Servicios', kind: MovementKind.expense, icon: 'zap', color: 0xFFFFCC00),
      Category(id: 'health', name: 'Salud', kind: MovementKind.expense, icon: 'heartPulse', color: 0xFFFF375F),
      Category(id: 'leisure', name: 'Ocio', kind: MovementKind.expense, icon: 'popcorn', color: 0xFFBF5AF2),
      Category(id: 'shopping', name: 'Compras', kind: MovementKind.expense, icon: 'shoppingBag', color: 0xFFFF6482),
      Category(id: 'education', name: 'Educación', kind: MovementKind.expense, icon: 'graduationCap', color: 0xFF5E5CE6),
      Category(
        id: kSubscriptionsCategoryId,
        name: 'Suscripciones',
        kind: MovementKind.expense,
        icon: 'repeat',
        color: 0xFF64D2FF,
        reserved: true,
      ),
      Category(id: 'expense_other', name: 'Otros', kind: MovementKind.expense, icon: 'ellipsis', color: 0xFF8E8E93),
      Category(id: 'salary', name: 'Sueldo', kind: MovementKind.income, icon: 'briefcase', color: 0xFF0FA47A),
      Category(id: 'freelance', name: 'Freelance', kind: MovementKind.income, icon: 'laptop', color: 0xFF30B0C7),
      Category(id: 'sales', name: 'Ventas', kind: MovementKind.income, icon: 'store', color: 0xFFFF9F0A),
      Category(id: 'transfer_in', name: 'Transferencia recibida', kind: MovementKind.income, icon: 'arrowDownLeft', color: 0xFF0A84FF),
      Category(id: kOtherIncomeCategoryId, name: 'Otros', kind: MovementKind.income, icon: 'ellipsis', color: 0xFF8E8E93),
    ];
