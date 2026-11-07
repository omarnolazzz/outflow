import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config/firebase_config.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/storage/local_store.dart';
import '../../../core/storage/sync_scope.dart';
import '../../account/presentation/session_controller.dart';
import '../../wallet/domain/wallet_settings.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../data/cloud_wallet_store.dart';
import '../domain/migration_plan.dart';

/// - [idle]: sin cuenta real o sin Firebase (vista previa, web): todo es local.
/// - [syncing]: decidiendo o migrando; nada local se sube todavía.
/// - [needsChoice]: ambos lados tienen datos; espera a "Unir" o "Usar solo los de la nube".
/// - [live]: espejo en vivo en los dos sentidos.
/// - [unavailable]: la nube no respondió o negó el permiso; la app sigue en local
///   y se reintenta al volver a primer plano.
enum CloudSyncState { idle, needsChoice, syncing, live, unavailable }

/// Almacén de la wallet en la nube de la cuenta abierta; null en la vista
/// previa, en la web, sin Firebase o sin cuenta.
final cloudWalletStoreProvider = Provider<CloudWalletStore?>((ref) {
  final uid = ref.watch(currentAccountProvider.select((a) => a?.uid));
  final auth = ref.watch(authServiceProvider);
  if (kIsWeb || !FirebaseConfig.usable || !auth.verifiesIdentity || uid == null) return null;
  return FirestoreCloudWalletStore(FirebaseFirestore.instance, uid, writer: ref.read(localStoreProvider).installToken);
});

/// Directorio privado de la app donde se guarda la copia de otra cuenta.
final cloudBackupDirProvider = Provider<Future<Directory> Function()>((ref) => getApplicationDocumentsDirectory);

/// Lo que se espera al servidor en `readAll`, `uploadAll`, `resetAt` y `wipe`.
final cloudTimeoutProvider = Provider<Duration>((ref) => const Duration(seconds: 30));

/// Tras descargar una wallet completa: si ya estaba configurada (reinstalar),
/// la sesión no repite la configuración inicial.
final walletDownloadedProvider = Provider<void Function()>((ref) => () {
      if (ref.read(sessionControllerProvider) is! NeedsOnboarding) return;
      if (!ref.read(walletSettingsRepositoryProvider).read().onboardingDone) return;
      ref.read(sessionControllerProvider.notifier).finishOnboarding();
    });

/// Lo que la sesión avisa al borrar toda la información. No depende de la
/// sesión (Riverpod no admite el ciclo sesión → espejo → sesión): el espejo se
/// registra aquí al construirse; sin espejo activo no hace nada.
class CloudEraseHooks {
  Future<bool> Function(DateTime at, bool? expectCloud)? _begin;
  void Function(DateTime at, {required bool completed})? _end;

  /// Falso si la nube ya no coincide con lo que el usuario vio en el diálogo
  /// ([expectCloud]): no se hizo nada y hay que volver a preguntar.
  Future<bool> begin(DateTime at, {bool? expectCloud}) async => await _begin?.call(at, expectCloud) ?? true;

  /// [completed] es falso si el borrado local falló a medias.
  void end(DateTime at, {required bool completed}) => _end?.call(at, completed: completed);
}

final cloudEraseHooksProvider = Provider<CloudEraseHooks>((ref) => CloudEraseHooks());

/// Migración una vez y espejo en vivo de la wallet (se observa en `app.dart`).
final cloudSyncProvider = NotifierProvider<CloudSync, CloudSyncState>(CloudSync.new);

final cloudSyncStateProvider = Provider<CloudSyncState>((ref) => ref.watch(cloudSyncProvider));

String _migratedKey(String uid) => 'outflow.cloud.migrated.$uid';
String _loadedAtKey(String uid) => 'outflow.cloud.loadedAt.$uid';

/// Una primera subida empezada y no confirmada: guarda el id de esta instalación.
String _uploadingKey(String uid) => 'outflow.cloud.uploading.$uid';

/// Un "Borrar toda la información" cuya parte en la nube aún no terminó.
String _pendingWipeKey(String uid) => 'outflow.cloud.pendingWipe.$uid';

/// Id de esta instalación (caja de ajustes, no se sincroniza). El llavero del
/// iPhone sobrevive a reinstalar y Hive no: la marca de migrado solo vale si
/// coincide con este id.
const _installId = LocalStore.installKey;
const _walletSettingsId = 'wallet.settings';

final List<String> _cloudBoxes = [...kSyncedBoxes, LocalStore.settingsBox];

typedef _Key = (String box, String id);

/// Una operación que quedó vieja (otra la reemplazó o se cerró la sesión).
class _Stale implements Exception {
  const _Stale();
}

/// Todo lo de una cuenta abierta; se descarta al cerrar sesión o cambiar de cuenta.
class _Run {
  _Run({
    required this.uid,
    required this.cloud,
    required this.store,
    required this.secure,
    required this.timeout,
    required this.backupDir,
  });

  final String uid;
  final CloudWalletStore cloud;
  final LocalStore store;
  final FlutterSecureStorage secure;
  final Duration timeout;
  final Future<Directory> Function() backupDir;

  bool alive = true;

  /// Cambia con cada operación: una anterior que despierte después no sigue.
  int epoch = 0;

  /// Los cambios locales se envían a la nube al momento.
  bool forwarding = false;

  /// Se está borrando toda la información: no se envía ni se aplica nada.
  bool paused = false;

  /// Se restauró la copia de esta cuenta: se borra al quedar en la nube.
  bool restoredBackup = false;

  StreamSubscription<StoreChange>? local;
  final watches = <StreamSubscription<CloudSnapshot>>[];

  /// Envíos en curso por id, con el `seq` del pendiente que llevan (para no
  /// repetir uno que sigue esperando a la red).
  final sending = <_Key, int>{};

  /// Las escrituras en curso (el borrado espera a que terminen, con límite).
  final sends = <Future<void>>{};

  /// El borrado en curso es de una wallet ya migrada (si no, la nube no se toca).
  bool erasingMigrated = false;

  /// El `beforeChange` que este run puso en [store].
  Object? hook;

  /// Cambios remotos que esperan a un snapshot sin escrituras pendientes, o
  /// borrados de caché que esperan al servidor. caja -> id -> json.
  final deferred = <String, Map<String, Map<String, Object?>?>>{};

  /// Aplica lo remoto en orden.
  Future<void> remote = Future.value();

  /// La parte en la nube de un borrado en curso.
  Future<void>? wipe;

  /// Hay un cambio local sin confirmar: lo remoto no lo pisa.
  bool busy(_Key k) => store.isDirty(k.$1, k.$2);
}

class CloudSync extends Notifier<CloudSyncState> {
  _Run? _run;

  /// Distingue cada cambio anotado como pendiente.
  int _seq = DateTime.now().microsecondsSinceEpoch;

  @override
  CloudSyncState build() {
    ref.read(cloudEraseHooksProvider)
      .._begin = beginErase
      .._end = endErase;
    final uid = ref.watch(currentAccountProvider.select((a) => a?.uid));
    final cloud = ref.watch(cloudWalletStoreProvider);
    if (uid == null || cloud == null) {
      _run = null;
      return CloudSyncState.idle;
    }
    final run = _Run(
      uid: uid,
      cloud: cloud,
      store: ref.read(localStoreProvider),
      secure: ref.read(secureStorageProvider),
      timeout: ref.read(cloudTimeoutProvider),
      backupDir: ref.read(cloudBackupDirProvider),
    );
    _run = run;
    // Desde ya: lo que se edite mientras se decide no se pierde. El pendiente
    // se anota antes del dato y otra vez después (con un seq nuevo).
    Future<void> hook(String box, Iterable<String> ids, {required bool deleted}) =>
        _beforeLocal(run, box, ids, deleted: deleted);
    run.hook = hook;
    run.store.beforeChange = hook;
    run.local = run.store.changes.listen((c) => _onLocal(run, c));
    ref.onDispose(() => _dispose(run));
    Future.microtask(() => _op(run, (epoch) => _connect(run, epoch)));
    return CloudSyncState.syncing;
  }

  // ---------------------------------------------------------------- acciones

  /// "Unir": sube solo lo que la nube no tiene y deja ambos lados iguales.
  Future<void> chooseMerge() async {
    final run = _run;
    if (run == null || state != CloudSyncState.needsChoice) return;
    await _op(run, (epoch) async {
      _set(run, CloudSyncState.syncing);
      final cloud = await _net(run, epoch, run.cloud.readAll());
      final reset = await _net(run, epoch, run.cloud.resetAt());
      final local = _snapshot(run);
      // Lo de antes va en la unión; lo editado desde aquí gana y se envía al quedar en vivo.
      await run.store.clearAllDirty();
      final up = mergeForUpload(local: local, cloud: cloud);
      if (up.values.any((b) => b.isNotEmpty)) await _net(run, epoch, run.cloud.uploadAll(up));
      await _replace(run, epoch, _overlay(cloud, up));
      await _markMigrated(run, epoch, reset);
      _downloaded(run);
      _goLive(run);
    });
  }

  /// "Usar solo los de la nube": lo local se descarta (ya se confirmó en la UI).
  Future<void> chooseCloudOnly() async {
    final run = _run;
    if (run == null || state != CloudSyncState.needsChoice) return;
    await _op(run, (epoch) async {
      _set(run, CloudSyncState.syncing);
      final cloud = await _net(run, epoch, run.cloud.readAll());
      final reset = await _net(run, epoch, run.cloud.resetAt());
      await run.store.clearAllDirty();
      await _replace(run, epoch, cloud);
      await _markMigrated(run, epoch, reset);
      _downloaded(run);
      _goLive(run);
    });
  }

  /// Si "Borrar toda la información" también vaciará la nube: solo cuando esta
  /// instalación ya migró la wallet de la cuenta abierta (igual que [beginErase]).
  Future<bool> willEraseCloud() async {
    final run = _run;
    if (run == null) return false;
    return _isMigrated(run, run.uid);
  }

  /// Reintenta tras [CloudSyncState.unavailable] (aviso tocado o al volver).
  Future<void> retry() async {
    final run = _run;
    if (run == null || state != CloudSyncState.unavailable) return;
    await _op(run, (epoch) => _connect(run, epoch));
  }

  /// Al volver a primer plano: reintenta, o comprueba si otro dispositivo
  /// borró todo (`resetAt`).
  Future<void> onResume() async {
    final run = _run;
    if (run == null) return;
    switch (state) {
      case CloudSyncState.unavailable:
        await retry();
      case CloudSyncState.live:
        await _op(run, (epoch) async {
          try {
            if (await _checkReset(run, epoch)) {
              _goLive(run);
              return;
            }
          } on CloudUnavailable catch (e) {
            // Sin red el espejo sigue (las escrituras se encolan), salvo que el
            // reinicio ya hubiera empezado.
            if (e.permissionDenied || !run.forwarding) rethrow;
          } on TimeoutException {
            if (!run.forwarding) rethrow;
          }
          // Lo rechazado o aún sin confirmar se reintenta.
          _flushDirty(run);
        });
      case CloudSyncState.idle || CloudSyncState.syncing || CloudSyncState.needsChoice:
        return;
    }
  }

  /// Antes de "Borrar toda la información": el espejo deja de enviar y de
  /// aplicar. Si la wallet ya estaba en la nube, empieza a vaciarla (sin esperar
  /// al servidor); si no, la nube no se toca y luego se vuelve a decidir.
  Future<bool> beginErase(DateTime at, [bool? expectCloud]) async {
    final run = _run;
    final migrated = run != null && await _isMigratedSafe(run, run.uid);
    // Si cambió desde que se mostró el diálogo, no se borra la nube sin avisar.
    if (expectCloud != null && expectCloud != migrated) return false;
    if (run == null) return true;
    run.epoch++;
    run.paused = true;
    run.forwarding = false;
    _stopWatches(run);
    run.erasingMigrated = migrated;
    if (!run.erasingMigrated) return true;
    try {
      // Si la app se cierra antes de terminar, se completa en la próxima
      // apertura de esta misma instalación.
      final token = await _installToken(run);
      await run.secure.write(
        key: _pendingWipeKey(run.uid),
        value: jsonEncode({'token': token, 'at': at.toUtc().toIso8601String()}),
      );
      await run.secure.write(key: _loadedAtKey(run.uid), value: at.toUtc().toIso8601String());
    } catch (e) {
      debugPrint('No se pudo anotar el borrado en la nube: ${e.runtimeType}');
    }
    await run.store.clearAllDirty();
    // Lo que ya iba camino de la nube llega antes del borrado, no después.
    final inFlight = run.sends.toList();
    _trackWipe(run, () async {
      try {
        await Future.wait(inFlight).timeout(const Duration(seconds: 3));
      } catch (_) {
        // Sin red o rechazado: no frena el borrado.
      }
      await run.cloud.wipe(at);
    }());
    return true;
  }

  /// La marca de migrado, sin colgar ni fallar: ante la duda, la nube no se toca.
  Future<bool> _isMigratedSafe(_Run run, String uid) async {
    try {
      return await _isMigrated(run, uid).timeout(run.timeout);
    } catch (e) {
      debugPrint('No se pudo leer la marca de migrado: ${e.runtimeType}');
      return false;
    }
  }

  /// Un único borrado en la nube a la vez: si uno agotó la espera local pero
  /// sigue en curso, el siguiente lo espera en vez de lanzar otro encima.
  Future<void> _trackWipe(_Run run, Future<void> wipe) {
    run.wipe = wipe;
    wipe.then<void>((_) {}, onError: (Object _) {
      if (identical(run.wipe, wipe)) run.wipe = null;
    });
    return wipe;
  }

  Future<void> _wipe(_Run run, int epoch, DateTime at) async {
    final started = run.wipe ?? _trackWipe(run, run.cloud.wipe(at));
    await _net(run, epoch, started);
    if (identical(run.wipe, started)) run.wipe = null;
  }

  /// Tras vaciar el teléfono: cuando la nube quede vacía sube la wallet nueva
  /// y vuelve el espejo.
  void endErase(DateTime at, {required bool completed}) {
    final run = _run;
    if (run == null) return;
    run.paused = false;
    if (!run.erasingMigrated) {
      // Sin marca: lo local quedó vacío y la migración se decide de nuevo.
      unawaited(_op(run, (epoch) => _connect(run, epoch)));
      return;
    }
    if (!completed) {
      // No se sube una wallet a medio borrar. El borrado en la nube queda
      // anotado y se completa al reintentar o en la próxima apertura.
      run.epoch++;
      _set(run, CloudSyncState.unavailable);
      return;
    }
    unawaited(_op(run, (epoch) async {
      _set(run, CloudSyncState.syncing);
      await _finishErase(run, epoch, at, leftover: false);
    }));
  }

  // -------------------------------------------------------------- conexión

  Future<void> _connect(_Run run, int epoch) async {
    _set(run, CloudSyncState.syncing);
    final uid = run.uid;

    final wipeAt = await _readPendingWipe(run);
    _guard(run, epoch);
    if (wipeAt != null) {
      await _finishErase(run, epoch, wipeAt, leftover: true);
      return;
    }

    // Un borrado que agotó la espera sigue en curso: nada se sube encima.
    final pendingWipe = run.wipe;
    if (pendingWipe != null) {
      await _net(run, epoch, pendingWipe);
      if (identical(run.wipe, pendingWipe)) run.wipe = null;
    }

    final owner = _localOwner(run);
    if (isForeignOwner(owner, uid)) {
      await run.secure.delete(key: _uploadingKey(uid));
      await _evict(run, epoch, owner!);
    }

    if (await _isMigrated(run, uid)) {
      _guard(run, epoch);
      // La decisión ya se tomó en esta instalación. Lo editado queda anotado
      // como pendiente y solo se envía tras comprobar que nadie borró todo.
      // Sin red entra en vivo igual (las escrituras se encolan) y la comprobación
      // se repite al volver a primer plano; un permiso denegado sí se avisa.
      await _checkReset(run, epoch, tolerateOffline: true);
      _goLive(run);
      return;
    }
    _guard(run, epoch);

    if (await _uploadInterrupted(run)) {
      _guard(run, epoch);
      await _resumeUpload(run, epoch);
      return;
    }
    _guard(run, epoch);

    final cloud = await _net(run, epoch, run.cloud.readAll());
    final reset = await _net(run, epoch, run.cloud.resetAt());

    // La copia que dejó esta cuenta cuando entró otra en el teléfono.
    final backup = await _readBackup(run, uid);
    _guard(run, epoch);
    if (backup != null) {
      final (:docs, :savedAt) = backup;
      if (reset != null && (savedAt == null || reset.isAfter(savedAt))) {
        // La cuenta borró todo después de la copia: no se resucita.
        await _deleteBackup(run, uid);
      } else if (isEffectivelyEmpty(_snapshot(run))) {
        await _applyExact(run, epoch, docs, (box, id, doc, _) => doc);
        run.restoredBackup = true;
        await _claimOwner(run);
      }
      _guard(run, epoch);
    }

    final local = _snapshot(run);
    switch (decideMigration(local: local, cloud: cloud, uid: uid, localOwner: _localOwner(run))) {
      case MigrationCase.upload:
        // Lo editado mientras sube queda pendiente y se envía al terminar.
        await run.store.clearAllDirty();
        // Si la subida se corta, al reintentar se sigue con lo local (no se pregunta).
        await run.secure.write(key: _uploadingKey(uid), value: await _installToken(run));
        await _net(run, epoch, run.cloud.uploadAll(_toCloudAll(local)));
        await _markMigrated(run, epoch, reset);
        _goLive(run);
      case MigrationCase.download:
        // Lo local es solo lo predeterminado: lo de la nube lo reemplaza.
        await run.store.clearAllDirty();
        await _replace(run, epoch, cloud);
        await _markMigrated(run, epoch, reset);
        _downloaded(run);
        _goLive(run);
      case MigrationCase.ask:
        // La app sigue con lo local; lo editado entra en lo que se una.
        _set(run, CloudSyncState.needsChoice);
      case MigrationCase.foreign:
        throw StateError('La wallet de otra cuenta debió apartarse antes');
    }
  }

  /// Esta instalación empezó la primera subida y no llegó a confirmarla.
  Future<bool> _uploadInterrupted(_Run run) async {
    final mark = await run.secure.read(key: _uploadingKey(run.uid));
    if (mark == null) return false;
    if (mark == await _installToken(run)) return true;
    // De otra instalación (el llavero del iPhone sobrevive a reinstalar): se olvida.
    await run.secure.delete(key: _uploadingKey(run.uid));
    return false;
  }

  /// Sigue la subida cortada con lo local por encima: se sube todo lo de este
  /// teléfono y se borra de la nube lo que esta instalación subió y ya no existe aquí.
  Future<void> _resumeUpload(_Run run, int epoch) async {
    final reset = await _net(run, epoch, run.cloud.resetAt());
    final mine = await _net(run, epoch, run.cloud.idsWrittenBy(await _installToken(run)));
    final local = _snapshot(run);
    await run.store.clearAllDirty();
    for (final e in mine.entries) {
      for (final id in e.value) {
        if (local[e.key]?[id] == null) await _net(run, epoch, run.cloud.delete(e.key, id));
      }
    }
    await _net(run, epoch, run.cloud.uploadAll(_toCloudAll(local)));
    await _markMigrated(run, epoch, reset);
    _goLive(run);
  }

  /// Otra cuenta en el teléfono: su wallet nunca se sube ni se muestra. Si no
  /// está ya en su nube, se guarda una copia privada; luego se vacía lo local.
  Future<void> _evict(_Run run, int epoch, String owner) async {
    final snapshot = _snapshot(run);
    final ownerInCloud = await _isMigrated(run, owner);
    _guard(run, epoch);
    if (!ownerInCloud && !isEffectivelyEmpty(snapshot)) await _writeBackup(run, owner, snapshot);
    _guard(run, epoch);
    await run.store.clearAllDirty();
    for (final box in _cloudBoxes) {
      final ids = run.store.readById(box).keys.where((id) => isSynced(box, id));
      await run.store.applyRemoteAll(box, {for (final id in ids) id: null});
      _guard(run, epoch);
    }
    await run.store.applyRemote(LocalStore.settingsBox, _walletSettingsId, WalletSettings(ownerUid: run.uid).toJson());
  }

  /// `resetAt` más nuevo que la última carga: otro dispositivo borró todo. Lo
  /// local se reemplaza por la nube sin enviar nada. Devuelve si hubo reinicio.
  Future<bool> _checkReset(_Run run, int epoch, {bool tolerateOffline = false}) async {
    final DateTime? reset;
    try {
      reset = await _net(run, epoch, run.cloud.resetAt());
    } on CloudUnavailable catch (e) {
      if (!tolerateOffline || e.permissionDenied) rethrow;
      return false;
    } on TimeoutException {
      if (!tolerateOffline) rethrow;
      return false;
    }
    if (reset == null) return false;
    final loaded = await _readDate(run, _loadedAtKey(run.uid));
    _guard(run, epoch);
    if (loaded != null && !reset.isAfter(loaded)) return false;
    // Lo pendiente de aquí es de la wallet anterior: se descarta, no se envía.
    run.forwarding = false;
    _stopWatches(run);
    await run.store.clearAllDirty();
    final cloud = await _net(run, epoch, run.cloud.readAll());
    await _replace(run, epoch, cloud);
    await _stampLoaded(run, reset);
    _downloaded(run);
    return true;
  }

  /// Termina un borrado: vacía la nube y sube la wallet nueva. Con [leftover]
  /// (anotado en otra apertura), antes mira si otro dispositivo escribió
  /// después; entonces no se borra nada y se descarga.
  Future<void> _finishErase(_Run run, int epoch, DateTime at, {required bool leftover}) async {
    if (leftover) {
      final last = await _net(run, epoch, run.cloud.lastChangeAt());
      if (last != null && last.isAfter(at)) {
        await run.secure.delete(key: _pendingWipeKey(run.uid));
        _guard(run, epoch);
        final cloud = await _net(run, epoch, run.cloud.readAll());
        final reset = await _net(run, epoch, run.cloud.resetAt());
        await run.store.clearAllDirty();
        await _replace(run, epoch, cloud);
        await _markMigrated(run, epoch, reset);
        _downloaded(run);
        _goLive(run);
        return;
      }
    }
    await _wipe(run, epoch, at);
    final local = _snapshot(run);
    await run.store.clearAllDirty();
    await _net(run, epoch, run.cloud.uploadAll(_toCloudAll(local)));
    await _markMigrated(run, epoch, at);
    await run.secure.delete(key: _pendingWipeKey(run.uid));
    _guard(run, epoch);
    _goLive(run);
  }

  /// La hora del borrado pendiente de esta instalación; uno de otra (el llavero
  /// del iPhone sobrevive a reinstalar) se olvida.
  Future<DateTime?> _readPendingWipe(_Run run) async {
    final raw = await run.secure.read(key: _pendingWipeKey(run.uid));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map;
      final token = run.store.read(LocalStore.settingsBox, _installId)?['token'];
      final at = DateTime.tryParse(json['at'] as String? ?? '');
      if (at != null && token != null && json['token'] == token) return at;
    } catch (_) {
      // Formato desconocido: se olvida.
    }
    await run.secure.delete(key: _pendingWipeKey(run.uid));
    return null;
  }

  void _goLive(_Run run) {
    run.forwarding = true;
    // Antes de escuchar: lo pendiente sale primero y lo remoto no lo pisa.
    _flushDirty(run);
    _startWatches(run);
    _set(run, CloudSyncState.live);
  }

  // --------------------------------------------------------- local → nube

  /// Antes de escribir: el pendiente queda en Hive primero.
  Future<void> _beforeLocal(_Run run, String box, Iterable<String> ids, {required bool deleted}) async {
    if (!run.alive || run.paused) return;
    final synced = [for (final id in ids) if (isSynced(box, id)) id];
    if (synced.isEmpty) return;
    try {
      await run.store.markDirtyAll(box, synced, deleted: deleted, seq: ++_seq);
    } catch (e) {
      debugPrint('No se pudo anotar un cambio pendiente: ${e.runtimeType}');
    }
  }

  void _onLocal(_Run run, StoreChange c) {
    if (!run.alive || run.paused || !isSynced(c.box, c.id)) return;
    final key = (c.box, c.id);
    // Primero queda anotado en Hive; solo entonces se intenta la red.
    run.store.markDirty(c.box, c.id, deleted: c.json == null, seq: ++_seq).then<void>(
      (_) {
        if (run.alive && run.forwarding && !run.paused) _send(run, key);
      },
      onError: (Object e) => debugPrint('No se pudo anotar un cambio pendiente: ${e.runtimeType}'),
    );
  }

  /// Envía lo pendiente que no esté ya en camino.
  void _flushDirty(_Run run) {
    for (final k in run.store.dirtyKeys()) {
      if (isSynced(k.$1, k.$2)) _send(run, k);
    }
  }

  /// Sin esperar al servidor: sin red no termina hasta que vuelve. El
  /// pendiente solo se quita cuando el servidor confirma ese mismo cambio.
  void _send(_Run run, _Key key) {
    final (box, id) = key;
    final seq = run.store.dirtySeq(box, id);
    if (seq == null || run.sending[key] == seq) return;
    final json = run.store.read(box, id);
    run.sending[key] = seq;
    Future<void> write;
    try {
      write = json == null ? run.cloud.delete(box, id) : run.cloud.put(box, id, toCloud(box, id, json));
    } catch (e) {
      write = Future.error(e);
    }
    run.sends.add(write);
    void settled() {
      run.sends.remove(write);
      if (run.sending[key] == seq) run.sending.remove(key);
    }

    write.then<void>((_) async {
      settled();
      await run.store.clearDirty(box, id, seq: seq);
    }, onError: (Object e) {
      // Queda pendiente: se reintenta al volver a primer plano o al reabrir.
      settled();
      if (!run.alive) return;
      debugPrint('No se pudo guardar en la nube: ${e.runtimeType}');
      if (e is CloudUnavailable && e.permissionDenied) _unavailable(run, permissionDenied: true);
    }).catchError((Object e) {
      debugPrint('No se pudo quitar el pendiente: ${e.runtimeType}');
    });
  }

  // --------------------------------------------------------- nube → local

  void _startWatches(_Run run) {
    _stopWatches(run);
    for (final box in _cloudBoxes) {
      run.watches.add(run.cloud.watch(box).listen(
            (s) => _onRemote(run, box, s),
            onError: (Object e) {
              debugPrint('No se pudo escuchar la wallet en la nube: ${e.runtimeType}');
              _unavailable(run, permissionDenied: e is CloudUnavailable && e.permissionDenied);
            },
          ));
    }
  }

  void _stopWatches(_Run run) {
    for (final w in run.watches) {
      w.cancel();
    }
    run.watches.clear();
    run.deferred.clear();
  }

  void _onRemote(_Run run, String box, CloudSnapshot s) {
    if (!run.alive || run.paused) return;
    final waiting = run.deferred.putIfAbsent(box, () => {});
    for (final d in s.changes) {
      waiting.remove(d.id);
      waiting[d.id] = d.json;
    }
    // Con escrituras propias sin confirmar, se espera al siguiente snapshot.
    if (s.hasPendingWrites || waiting.isEmpty) return;
    final batch = Map.of(waiting);
    waiting.clear();
    final fromCache = s.fromCache;
    run.remote = run.remote.then((_) => _applyRemote(run, box, batch, fromCache)).catchError((Object e) {
      debugPrint('No se pudo aplicar un cambio de la nube: ${e.runtimeType}');
    });
  }

  Future<void> _applyRemote(_Run run, String box, Map<String, Map<String, Object?>?> batch, bool fromCache) async {
    if (!run.alive || run.paused) return;
    final updates = <String, Map<String, Object?>?>{};
    for (final e in batch.entries) {
      final id = e.key;
      if (run.busy((box, id))) continue;
      final mine = run.store.read(box, id);
      final theirs = e.value;
      if (theirs == null) {
        // Un borrado solo cuenta si lo dice el servidor.
        if (fromCache) {
          run.deferred.putIfAbsent(box, () => {}).putIfAbsent(id, () => null);
        } else if (mine != null) {
          if (box == LocalStore.settingsBox && id == _walletSettingsId) {
            // Sin ajustes en la nube quedan solo los del dispositivo.
            final kept = fromCloud(box, id, const {}, mine);
            if (!jsonEquals(kept, mine)) updates[id] = kept;
          } else {
            updates[id] = null;
          }
        }
        continue;
      }
      final next = fromCloud(box, id, theirs, mine);
      if (!jsonEquals(next, mine)) updates[id] = next;
    }
    if (updates.isNotEmpty) await run.store.applyRemoteAll(box, updates);
  }

  // -------------------------------------------------------------- utilidades

  Future<void> _op(_Run run, Future<void> Function(int epoch) body) async {
    final epoch = ++run.epoch;
    bool current() => run.alive && run.epoch == epoch;
    try {
      await body(epoch);
    } on _Stale {
      // Otra operación tomó el relevo.
    } on CloudUnavailable catch (e) {
      debugPrint('Wallet en la nube no disponible (permiso denegado: ${e.permissionDenied})');
      if (current()) _unavailable(run, permissionDenied: e.permissionDenied);
    } on TimeoutException {
      debugPrint('La nube no respondió a tiempo');
      if (current()) _unavailable(run, permissionDenied: false);
    } catch (e) {
      debugPrint('No se pudo sincronizar la wallet: ${e.runtimeType}');
      if (current()) _unavailable(run, permissionDenied: false);
    }
  }

  void _guard(_Run run, int epoch) {
    if (!run.alive || run.epoch != epoch) throw const _Stale();
  }

  Future<T> _net<T>(_Run run, int epoch, Future<T> f) async {
    final r = await f.timeout(run.timeout);
    _guard(run, epoch);
    return r;
  }

  void _unavailable(_Run run, {required bool permissionDenied}) {
    if (!run.alive) return;
    _stopWatches(run);
    if (permissionDenied) run.forwarding = false;
    _set(run, CloudSyncState.unavailable);
  }

  void _set(_Run run, CloudSyncState s) {
    if (run.alive && identical(_run, run)) state = s;
  }

  void _dispose(_Run run) {
    run.alive = false;
    if (identical(run.store.beforeChange, run.hook)) run.store.beforeChange = null;
    run.local?.cancel();
    _stopWatches(run);
    if (identical(_run, run)) _run = null;
  }

  void _downloaded(_Run run) {
    if (!run.alive) return;
    try {
      ref.read(walletDownloadedProvider)();
    } catch (e) {
      debugPrint('No se pudo cerrar la configuración inicial: ${e.runtimeType}');
    }
  }

  String? _localOwner(_Run run) => run.store.read(LocalStore.settingsBox, _walletSettingsId)?['ownerUid'] as String?;

  /// Lo sincronizado de este teléfono, en su forma local.
  WalletDocs _snapshot(_Run run) => {
        for (final box in _cloudBoxes)
          box: {
            for (final e in run.store.readById(box).entries)
              if (isSynced(box, e.key)) e.key: e.value,
          },
      };

  WalletDocs _toCloudAll(WalletDocs local) => {
        for (final b in local.entries)
          b.key: {for (final d in b.value.entries) d.key: toCloud(b.key, d.key, d.value)},
      };

  WalletDocs _overlay(WalletDocs base, WalletDocs top) => {
        for (final box in {...base.keys, ...top.keys}) box: {...?base[box], ...?top[box]},
      };

  /// Deja cada caja sincronizada exactamente como [cloud], conservando lo del
  /// dispositivo. Lo editado y aún sin enviar no se pisa.
  Future<void> _replace(_Run run, int epoch, WalletDocs cloud) async {
    await _applyExact(run, epoch, cloud, (box, id, doc, mine) => fromCloud(box, id, doc, mine));
    await _claimOwner(run);
    _guard(run, epoch);
  }

  Future<void> _applyExact(
    _Run run,
    int epoch,
    WalletDocs docs,
    Map<String, Object?> Function(String box, String id, Map<String, Object?> doc, Map<String, Object?>? mine) toLocal,
  ) async {
    for (final box in _cloudBoxes) {
      final remote = docs[box] ?? const <String, Map<String, Object?>>{};
      final local = run.store.readById(box);
      final updates = <String, Map<String, Object?>?>{};
      for (final id in {...local.keys, ...remote.keys}) {
        if (!isSynced(box, id) || run.busy((box, id))) continue;
        final mine = local[id];
        final theirs = remote[id];
        final Map<String, Object?>? next;
        if (theirs != null) {
          next = toLocal(box, id, theirs, mine);
        } else if (box == LocalStore.settingsBox && id == _walletSettingsId && mine != null) {
          // Sin ajustes en la nube quedan solo los del dispositivo.
          next = fromCloud(box, id, const {}, mine);
        } else {
          next = null;
        }
        if (next == null ? mine != null : !jsonEquals(next, mine)) updates[id] = next;
      }
      // Si mientras tanto se empezó a borrar todo o cambió la cuenta, se para.
      _guard(run, epoch);
      if (updates.isNotEmpty) await run.store.applyRemoteAll(box, updates);
    }
  }

  /// La wallet local queda a nombre de la cuenta que entra (sin enviar nada).
  Future<void> _claimOwner(_Run run) async {
    final json = run.store.read(LocalStore.settingsBox, _walletSettingsId) ?? const <String, Object?>{};
    if (json['ownerUid'] == run.uid) return;
    await run.store.applyRemote(LocalStore.settingsBox, _walletSettingsId, {...json, 'ownerUid': run.uid});
  }

  /// El mismo id que firma los documentos en la nube (`writer`).
  Future<String> _installToken(_Run run) async => run.store.installToken();

  Future<bool> _isMigrated(_Run run, String uid) async {
    final mark = await run.secure.read(key: _migratedKey(uid));
    return mark != null && mark == run.store.read(LocalStore.settingsBox, _installId)?['token'];
  }

  /// Solo tras la confirmación del servidor o la descarga completa.
  Future<void> _markMigrated(_Run run, int epoch, DateTime? reset) async {
    _guard(run, epoch);
    await run.secure.write(key: _migratedKey(run.uid), value: await _installToken(run));
    await run.secure.delete(key: _uploadingKey(run.uid));
    await _stampLoaded(run, reset);
    if (run.restoredBackup) {
      run.restoredBackup = false;
      await _deleteBackup(run, run.uid);
    }
    _guard(run, epoch);
  }

  /// Con relojes distintos, nunca antes del `resetAt` que ya se cargó.
  Future<void> _stampLoaded(_Run run, DateTime? reset) async {
    final now = DateTime.now();
    final at = reset != null && reset.isAfter(now) ? reset : now;
    await run.secure.write(key: _loadedAtKey(run.uid), value: at.toUtc().toIso8601String());
  }

  Future<DateTime?> _readDate(_Run run, String key) async {
    final v = await run.secure.read(key: key);
    return v == null ? null : DateTime.tryParse(v);
  }

  // ------------------------------------------------------------------ copia

  Future<File> _backupFile(_Run run, String owner) async {
    final dir = await run.backupDir();
    final safe = owner.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}/backup_$safe.json');
  }

  /// Nunca se escribe su contenido en los logs.
  Future<void> _writeBackup(_Run run, String owner, WalletDocs docs) async {
    final file = await _backupFile(run, owner);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({'ownerUid': owner, 'savedAt': DateTime.now().toUtc().toIso8601String(), 'docs': docs}),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  Future<({WalletDocs docs, DateTime? savedAt})?> _readBackup(_Run run, String owner) async {
    try {
      final file = await _backupFile(run, owner);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map;
      final raw = json['docs'] as Map;
      final savedAt = json['savedAt'];
      return (
        docs: <String, Map<String, Map<String, Object?>>>{
          for (final b in raw.entries)
            b.key as String: {
              for (final d in (b.value as Map).entries) d.key as String: (d.value as Map).cast<String, Object?>(),
            },
        },
        savedAt: savedAt is String ? DateTime.tryParse(savedAt) : null,
      );
    } catch (e) {
      debugPrint('No se pudo leer la copia local: ${e.runtimeType}');
      return null;
    }
  }

  Future<void> _deleteBackup(_Run run, String owner) async {
    try {
      final file = await _backupFile(run, owner);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('No se pudo borrar la copia local: ${e.runtimeType}');
    }
  }
}
