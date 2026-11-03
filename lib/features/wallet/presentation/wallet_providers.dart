import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/domain/billing_cycle.dart';
import '../../subscriptions/presentation/subscription_providers.dart';
import '../data/hive_account_repository.dart';
import '../data/hive_category_repository.dart';
import '../data/hive_movement_repository.dart';
import '../data/wallet_settings_repository.dart';
import '../domain/account_balances.dart';
import '../domain/category.dart';
import '../domain/charge_movements.dart';
import '../domain/month_summary.dart';
import '../domain/movement.dart';
import '../domain/wallet_account.dart';
import '../domain/wallet_settings.dart';

final movementRepositoryProvider = Provider<MovementRepository>(
  (ref) => HiveMovementRepository(ref.watch(localStoreProvider)),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => HiveCategoryRepository(ref.watch(localStoreProvider)),
);

final walletSettingsRepositoryProvider = Provider<WalletSettingsRepository>(
  (ref) => HiveWalletSettingsRepository(ref.watch(localStoreProvider)),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => HiveAccountRepository(ref.watch(localStoreProvider)),
);

/// Todas las cuentas, también las archivadas. Toda lectura de cuentas y saldos
/// pasa por aquí, así que quien actualiza desde una versión sin cuentas recibe
/// aquí su "Mi cuenta", en su moneda principal, sin depender de ninguna pantalla
/// ni estado de sesión. `ensureDefault` es idempotente.
final accountsProvider = StreamProvider<List<WalletAccount>>((ref) async* {
  final repo = ref.watch(accountRepositoryProvider);
  await repo.ensureDefault(ref.read(walletSettingsRepositoryProvider).read().currency);
  yield* repo.watchAll();
});

/// Saldo por id de cuenta. Mientras carga no hay saldos, en vez de saldos en 0.
final accountBalancesProvider = Provider<AsyncValue<Map<String, int>>>((ref) {
  final accounts = ref.watch(accountsProvider).value;
  final movements = ref.watch(movementsProvider).value;
  if (accounts == null || movements == null) return const AsyncLoading();
  return AsyncData(computeBalances(accounts, movements));
});

/// La cuenta que reciben los movimientos sin cuenta (null mientras carga).
final defaultAccountProvider = Provider<WalletAccount?>(
  (ref) => defaultAccountOf(ref.watch(accountsProvider).value ?? const []),
);

final movementsProvider = StreamProvider<List<Movement>>(
  (ref) => ref.watch(movementRepositoryProvider).watchAll(),
);

final categoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll(),
);

final walletSettingsProvider = StreamProvider<WalletSettings>(
  (ref) => ref.watch(walletSettingsRepositoryProvider).watch(),
);

/// Categorías por id (para pintar iconos y colores).
final categoryIndexProvider = Provider<Map<String, Category>>((ref) => {
      for (final c in ref.watch(categoriesProvider).value ?? const <Category>[]) c.id: c,
    });

/// Resumen de un mes (primer día del mes como clave).
final monthSummaryProvider = Provider.family<AsyncValue<MonthSummary>, DateTime>((ref, month) {
  final movements = ref.watch(movementsProvider);
  final subs = ref.watch(subscriptionsProvider);
  final settings = ref.watch(walletSettingsProvider);
  final now = ref.watch(nowProvider);
  if (movements.value == null || subs.value == null || settings.value == null) {
    return const AsyncLoading();
  }
  return AsyncData(MonthSummary.compute(
    movements: movements.value!,
    subscriptions: subs.value!,
    settings: settings.value!,
    month: month,
    now: now,
  ));
});

/// Mantiene los gastos de suscripciones al día con sus cobros. La app lo
/// observa mientras está abierta; la conciliación es idempotente, así que
/// reescribir datos no provoca un bucle.
final chargeMovementSyncProvider = Provider<void>((ref) {
  final subs = ref.watch(subscriptionsProvider).value;
  final movements = ref.watch(movementsProvider).value;
  final settings = ref.watch(walletSettingsProvider).value;
  final now = ref.watch(nowProvider);
  if (subs == null || movements == null || settings == null) return;

  final changes = reconcileChargeMovements(
    subscriptions: subs,
    existing: movements,
    settings: settings,
    now: now,
  );
  if (changes.upsert.isEmpty && changes.delete.isEmpty) return;
  final repo = ref.read(movementRepositoryProvider);
  Future.microtask(() async {
    if (changes.upsert.isNotEmpty) await repo.saveAll(changes.upsert);
    if (changes.delete.isNotEmpty) await repo.deleteAll(changes.delete);
  });
});

final walletActionsProvider = Provider<WalletActions>(
  (ref) => WalletActions(ref.watch(movementRepositoryProvider), ref.watch(walletSettingsRepositoryProvider)),
);

/// Comandos sobre movimientos (la UI no toca los repositorios).
class WalletActions {
  WalletActions(this._movements, this._settings);
  final MovementRepository _movements;
  final WalletSettingsRepository _settings;

  Future<void> save(Movement m) => _movements.save(m);

  /// Borra y devuelve el movimiento (para Deshacer). Un cobro de suscripción
  /// borrado se recuerda para que la conciliación no lo vuelva a crear.
  Future<Movement?> delete(String id) async {
    final all = await _movements.watchAll().first;
    final m = all.where((x) => x.id == id).firstOrNull;
    // Tu parte de un gasto compartido se gestiona desde Amigos.
    if (m == null || m.origin == MovementOrigin.split) return null;
    if (m.origin == MovementOrigin.subscription) {
      final s = _settings.read();
      await _settings.save(s.copyWith(deletedChargeIds: {...s.deletedChargeIds, id}));
    }
    await _movements.delete(id);
    return m;
  }

  /// "No me cobraron": quita el gasto del cobro [date] de la suscripción y lo
  /// recuerda para no recrearlo. Devuelve el borrado (para Deshacer).
  Future<Movement?> dropCharge(String subscriptionId, DateTime date) async {
    final id = chargeMovementId(subscriptionId, dateOnly(date));
    final s = _settings.read();
    await _settings.save(s.copyWith(deletedChargeIds: {...s.deletedChargeIds, id}));
    final all = await _movements.watchAll().first;
    final m = all.where((x) => x.id == id).firstOrNull;
    if (m != null) await _movements.delete(id);
    return m;
  }

  /// Recuerda que ya se respondió "¿Es este pago?" para el gasto compartido
  /// [expenseId], para no volver a preguntar.
  Future<void> dismissSplitMatch(String expenseId) async {
    final s = _settings.read();
    if (s.dismissedSplitMatchIds.contains(expenseId)) return;
    await _settings.save(s.copyWith(dismissedSplitMatchIds: {...s.dismissedSplitMatchIds, expenseId}));
  }

  Future<void> restore(Movement m) async {
    final s = _settings.read();
    if (s.deletedChargeIds.contains(m.id)) {
      await _settings.save(s.copyWith(deletedChargeIds: {...s.deletedChargeIds}..remove(m.id)));
    }
    await _movements.save(m);
  }
}

/// Los 6 meses que terminan en el mes dado (para el Resumen).
final lastMonthsProvider = Provider.family<AsyncValue<List<MonthSummary>>, DateTime>((ref, month) {
  final movements = ref.watch(movementsProvider).value;
  final subs = ref.watch(subscriptionsProvider).value;
  final settings = ref.watch(walletSettingsProvider).value;
  if (movements == null || subs == null || settings == null) return const AsyncLoading();
  return AsyncData(MonthSummary.lastMonths(
    6,
    movements: movements,
    subscriptions: subs,
    settings: settings,
    month: month,
    now: ref.watch(nowProvider),
  ));
});
