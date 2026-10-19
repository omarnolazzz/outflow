import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../storage/local_store.dart';

/// Dependencias de infraestructura. `localStoreProvider` se sobrescribe en
/// `main()` con la instancia ya abierta (la apertura es asíncrona).
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('Se sobrescribe en main()'),
);

/// "Ahora" inyectable: se invalida al volver a primer plano para que
/// "En 2 días" no se quede congelado si la app pasa la noche abierta.
final nowProvider = Provider<DateTime>((ref) => DateTime.now());
