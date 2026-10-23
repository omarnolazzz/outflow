import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/firebase_config.dart';
import '../../account/presentation/session_controller.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../data/firestore_social_repository.dart';
import '../data/social_repository.dart';
import '../domain/balances.dart';
import '../domain/shared_expense.dart';
import '../domain/split_movements.dart';

/// Firestore solo con Firebase configurado y una cuenta real de Google; en la
/// vista previa web o con la cuenta simulada, Amigos no está disponible.
final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  // Por uid: bloquear y desbloquear no recrea el repositorio ni sus streams.
  final uid = ref.watch(currentAccountProvider.select((a) => a?.uid));
  final auth = ref.watch(authServiceProvider);
  if (kIsWeb || !FirebaseConfig.isConfigured || !auth.verifiesIdentity || uid == null) {
    return const UnavailableSocialRepository();
  }
  return FirestoreSocialRepository(FirebaseFirestore.instance, uid);
});

final friendsProvider = StreamProvider<List<Person>>((ref) => ref.watch(socialRepositoryProvider).watchFriends());

final incomingRequestsProvider =
    StreamProvider<List<FriendRequest>>((ref) => ref.watch(socialRepositoryProvider).watchIncoming());

final outgoingRequestsProvider =
    StreamProvider<List<FriendRequest>>((ref) => ref.watch(socialRepositoryProvider).watchOutgoing());

/// Gastos compartidos del usuario. `fromCache` viene de los metadatos de
/// Firestore: solo un snapshot del servidor autoriza a borrar movimientos.
final sharedExpensesProvider =
    StreamProvider<ExpensesSnapshot>((ref) => ref.watch(socialRepositoryProvider).watchExpenses());

/// Saldo con cada amigo (deudas no saldadas).
final balancesProvider = Provider<List<Balance>>((ref) {
  final uid = ref.watch(currentAccountProvider.select((a) => a?.uid));
  final expenses = ref.watch(sharedExpensesProvider).value?.expenses;
  if (uid == null || expenses == null) return const [];
  return computeBalances(expenses, uid);
});

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
