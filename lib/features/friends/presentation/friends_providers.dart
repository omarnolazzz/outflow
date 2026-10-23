import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/presentation/session_controller.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../domain/split_movements.dart';

/// Gastos compartidos del usuario. Placeholder: la Task 3 lo rellena con Firestore.
final sharedExpensesProvider = StreamProvider<ExpensesSnapshot>(
  (ref) => Stream.value(const ExpensesSnapshot([], fromCache: true)),
);

/// Mantiene en la wallet tu parte de cada gasto compartido. Mismo patrón que
/// [chargeMovementSyncProvider]: conciliación idempotente, sin cuenta no hace nada.
final splitMovementSyncProvider = Provider<void>((ref) {
  final account = ref.watch(currentAccountProvider);
  final snapshot = ref.watch(sharedExpensesProvider).value;
  final movements = ref.watch(movementsProvider).value;
  final categories = ref.watch(categoriesProvider).value;
  if (account == null ||
      snapshot == null ||
      movements == null ||
      categories == null) {
    return;
  }

  final changes = reconcileSplitMovements(
    snapshot: snapshot,
    existing: movements,
    myUid: account.uid,
    categoryIds: {for (final c in categories) c.id},
  );
  if (changes.upsert.isEmpty && changes.delete.isEmpty) return;
  final repo = ref.read(movementRepositoryProvider);
  Future.microtask(() async {
    if (changes.upsert.isNotEmpty) await repo.saveAll(changes.upsert);
    if (changes.delete.isNotEmpty) await repo.deleteAll(changes.delete);
  });
});
