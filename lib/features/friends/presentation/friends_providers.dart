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
  final account = ref.read(currentAccountProvider);
  if (kIsWeb || !FirebaseConfig.isConfigured || !auth.verifiesIdentity || uid == null || account == null) {
    return const UnavailableSocialRepository();
  }
  return FirestoreSocialRepository(FirebaseFirestore.instance, account);
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

/// Gastos que cuentan para la wallet y los saldos: los que creaste tú o un
/// amigo aceptado. Quien solo conoce tu uid no puede meterte deudas ni gastos.
/// Null mientras cargan los gastos o los amigos (sin amigos aún no se sabe
/// qué gastos valen, y una lista vacía borraría tus movimientos `split`).
final trustedExpensesProvider = Provider<ExpensesSnapshot?>((ref) {
  final uid = ref.watch(currentAccountProvider.select((a) => a?.uid));
  final snapshot = ref.watch(sharedExpensesProvider).value;
  final friends = ref.watch(friendsProvider).value;
  if (uid == null || snapshot == null || friends == null) return null;
  final trusted = {uid, for (final f in friends) f.uid};
  return ExpensesSnapshot(
    [for (final e in snapshot.expenses) if (trusted.contains(e.createdBy)) e],
    fromCache: snapshot.fromCache,
  );
});

/// Saldo con cada persona (deudas no saldadas de los gastos de confianza).
final balancesProvider = Provider<List<Balance>>((ref) {
  final uid = ref.watch(currentAccountProvider.select((a) => a?.uid));
  final expenses = ref.watch(trustedExpensesProvider)?.expenses;
  if (uid == null || expenses == null) return const [];
  return computeBalances(expenses, uid);
});

/// Mantiene en la wallet tu parte de cada gasto compartido. Mismo patrón que
/// [chargeMovementSyncProvider]: conciliación idempotente, sin cuenta no hace nada.
final splitMovementSyncProvider = Provider<void>((ref) {
  final account = ref.watch(currentAccountProvider);
  final snapshot = ref.watch(trustedExpensesProvider);
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
