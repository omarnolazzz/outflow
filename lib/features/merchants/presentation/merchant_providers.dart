import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../data/hive_merchant_repository.dart';
import '../domain/entities/merchant.dart';
import '../domain/merchant_repository.dart';

final merchantRepositoryProvider = Provider<MerchantRepository>(
  (ref) => HiveMerchantRepository(ref.watch(localStoreProvider)),
);

final merchantsProvider = StreamProvider<List<Merchant>>(
  (ref) => ref.watch(merchantRepositoryProvider).watchAll(),
);

/// Índice id → comercio para resolver logos en listas sin búsquedas lineales.
final merchantIndexProvider = Provider<Map<String, Merchant>>((ref) {
  final list = ref.watch(merchantsProvider).value ?? const [];
  return {for (final m in list) m.id: m};
});

/// Comercio por id (null si no existe o no hay id).
final merchantByIdProvider = Provider.family<Merchant?, String?>(
  (ref, id) => id == null ? null : ref.watch(merchantIndexProvider)[id],
);
