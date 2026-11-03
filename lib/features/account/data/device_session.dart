import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/di/core_providers.dart';
import 'auth_providers.dart';

/// Lo último que se sabe del dispositivo que tiene abierta la cuenta.
class RemoteDevice {
  const RemoteDevice({required this.deviceId, required this.trusted});

  /// Null si el documento aún no existe.
  final String? deviceId;

  /// El dato viene del servidor y sin escrituras nuestras pendientes: ni de
  /// caché ni de un `claim` propio sin confirmar.
  final bool trusted;
}

/// Una cuenta de Google solo puede estar abierta en un dispositivo: el último
/// que entra gana y los demás se cierran.
abstract interface class DeviceSessionRepository {
  /// Marca este dispositivo como el de la cuenta. Sin red no termina hasta
  /// que vuelve la conexión: quien llame no debe esperarla.
  Future<void> claim(String uid, String deviceId);

  /// Dispositivo que tiene la cuenta abierta, con cada cambio.
  Stream<RemoteDevice> watch(String uid);
}

/// La sesión se perdió: otro dispositivo, confirmado por el servidor, tiene
/// la cuenta. Un dato de caché o una escritura propia pendiente no cuentan.
bool isSessionLost(RemoteDevice remote, String myDeviceId) =>
    remote.trusted && remote.deviceId != null && remote.deviceId != myDeviceId;

/// `sessions/{uid}` = `{deviceId, platform, updatedAt}`.
class FirestoreDeviceSessionRepository implements DeviceSessionRepository {
  FirestoreDeviceSessionRepository(this._db);
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _db.collection('sessions').doc(uid);

  @override
  Future<void> claim(String uid, String deviceId) => _doc(uid).set({
        'deviceId': deviceId,
        'platform': defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Stream<RemoteDevice> watch(String uid) => _doc(uid).snapshots(includeMetadataChanges: true).map((snap) {
        final m = snap.metadata;
        return RemoteDevice(
          deviceId: snap.data()?['deviceId'] as String?,
          trusted: !m.isFromCache && !m.hasPendingWrites,
        );
      });
}

/// Sin Firebase (vista previa, cuenta simulada): no hay otro dispositivo.
class NoDeviceSessionRepository implements DeviceSessionRepository {
  const NoDeviceSessionRepository();

  @override
  Future<void> claim(String uid, String deviceId) async {}

  @override
  Stream<RemoteDevice> watch(String uid) => const Stream.empty();
}

/// Mismo criterio que el repositorio social: Firestore solo con Firebase
/// configurado y una cuenta real de Google.
final deviceSessionRepositoryProvider = Provider<DeviceSessionRepository>((ref) {
  final auth = ref.watch(authServiceProvider);
  if (kIsWeb || !FirebaseConfig.usable || !auth.verifiesIdentity) return const NoDeviceSessionRepository();
  return FirestoreDeviceSessionRepository(FirebaseFirestore.instance);
});

const _deviceIdKey = 'outflow.device.id';

/// Id aleatorio de esta instalación, guardado en el llavero.
final deviceIdProvider = FutureProvider<String>((ref) async {
  final secure = ref.watch(secureStorageProvider);
  final saved = await secure.read(key: _deviceIdKey);
  if (saved != null && saved.isNotEmpty) return saved;
  final id = const Uuid().v4();
  await secure.write(key: _deviceIdKey, value: id);
  return id;
});
