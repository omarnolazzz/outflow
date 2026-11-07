# Outflow · Wallet en la nube Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que la wallet de cada cuenta de Google se guarde en Firestore y vuelva al reinstalar o cambiar de teléfono, sin perder lo que hoy está solo en el dispositivo.

**Architecture:** Hive sigue siendo el almacén local que lee toda la app (lecturas síncronas y sin red), y un **espejo** lo sincroniza en ambos sentidos con `wallets/{uid}/{caja}/{id}`. Los cambios locales suben por un gancho de `LocalStore`; los remotos se aplican en Hive por una vía que no vuelve a subirlos. Al entrar con Google se migra una vez: subir, preguntar Unir o Usar la nube, o descargar.

**Tech Stack:** Flutter 3.47.7, Riverpod 3, Hive CE, `cloud_firestore` 6.0.0 (versiones de Firebase fijas), `fake_cloud_firestore` 4.1.0+1 para pruebas.

**Spec:** `docs/superpowers/specs/2026-11-07-wallet-en-la-nube-design.md`

## Global Constraints
- Una sola wallet por cuenta: `wallets/{uid}`, de lectura y escritura solo para el dueño.
- **Se sincroniza:** cajas `movements`, `accounts`, `subscriptions`, `merchants`, `categories`; y en la caja `settings`, solo las claves `wallet.settings`, `notifications.globalRule` y `capture.sources`.
- **Solo dispositivo:** `account.preview`; los campos `faceIdEnabled` y `ownerUid` de `wallet.settings` (no suben y, al aplicar lo remoto, se conservan los locales); secure storage (id de dispositivo, clave de captura); bandejas; prefs nativas.
- Sin red: todo funciona en local; nunca se espera al servidor para guardar en la interfaz.
- Gana la última escritura por documento. Borrados en vivo en ambos sentidos.
- Nunca se mezclan dos cuentas: lo local solo se migra si `ownerUid` es la cuenta que entra, null, o la cuenta de vista previa.
- La vista previa o web sin Firebase sigue igual, solo local.
- Repositorio público: sin datos personales. `flutter analyze` limpio, `flutter test` verde; commits con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus
1. Un cambio remoto aplicado en Hive vuelve a subirse y se forma un bucle de escrituras. → test Task 1 y Task 3.
2. Reinstalación: nube con datos y teléfono vacío → descarga sin preguntar, y "Te queda" y los saldos son idénticos a los del otro teléfono. → test Task 3.
3. Reglas sin publicar (escritura denegada) → la app sigue en local, muestra el aviso, no marca migrado y reintenta en la siguiente apertura sin perder nada. → test Task 3.
4. Datos locales de otra cuenta en el teléfono → no se suben ni aparecen en la wallet de la cuenta que entra. → test Task 3.
5. Borrar toda la información en un teléfono, y el otro abre después → su caché se descarta por `resetAt` y no resucita nada. → test Task 3.

---

### Task 1: Gancho de cambios locales en `LocalStore`

**Files:**
- Modify: `lib/core/storage/local_store.dart`
- Create: `lib/core/storage/sync_scope.dart`
- Test: `test/local_store_hooks_test.dart`

**Interfaces:**
- Produces:
  - `class StoreChange { String box; String id; Map<String, Object?>? json; }`, donde `json == null` significa borrado.
  - `Stream<StoreChange> LocalStore.changes`: emite en `write`, `writeAll` (uno por id), `remove`, `removeAll` y `clearAll` (un borrado por id existente).
  - `Future<void> LocalStore.applyRemote(String box, String id, Map<String, Object?>? json)`: escribe o borra **sin** emitir en `changes`.
  - `Future<void> LocalStore.applyRemoteAll(String box, Map<String, Map<String, Object?>?> docs)`, en bloque y sin emitir.
  - En `sync_scope.dart`:
    - `const kSyncedBoxes = [movementsBox, accountsBox, subscriptionsBox, merchantsBox, categoriesBox]`;
    - `const kSyncedSettings = {'wallet.settings', 'notifications.globalRule', 'capture.sources'}`;
    - `bool isSynced(String box, String id)`;
    - `Map<String, Object?> toCloud(String box, String id, Map<String, Object?> json)`, que quita `faceIdEnabled` y `ownerUid` de `wallet.settings`;
    - `Map<String, Object?> fromCloud(String box, String id, Map<String, Object?> remote, Map<String, Object?>? local)`, que conserva los `faceIdEnabled` y `ownerUid` locales.
- [ ] **Step 1: Tests** (Hive real en un directorio temporal, como `test/erase_everything_test.dart`):
  - `write`, `remove` y `writeAll` de 3 elementos emiten 1, 1 y 3 cambios;
  - `applyRemote` y `applyRemoteAll` cambian los datos y no emiten nada;
  - `clearAll` emite un borrado por cada id;
  - `isSynced('settings','account.preview')` es false; `isSynced('settings','wallet.settings')` y `isSynced('movements','x')` son true;
  - `toCloud` de `wallet.settings` no lleva `faceIdEnabled` ni `ownerUid`;
  - `fromCloud` conserva el `faceIdEnabled` local.
- [ ] **Step 2: Run** `flutter test test/local_store_hooks_test.dart` → FAIL.
- [ ] **Step 3: Implement.** Las cajas actuales siguen igual; `openUnencrypted` también expone `changes`.
- [ ] **Step 4: Run** → PASS; `flutter test` completo.
- [ ] **Step 5: Commit** "Almacén local: avisa de cada cambio para sincronizarlo".

### Task 2: Almacén de la wallet en Firestore y reglas

**Files:**
- Create: `lib/features/cloud/data/cloud_wallet_store.dart`
- Modify: `firestore.rules`
- Test: `test/cloud_wallet_store_test.dart`

**Interfaces:**
- Consumes: `kSyncedBoxes`, `kSyncedSettings` (Task 1).
- Produces:
  - `class CloudDoc { String box; String id; Map<String, Object?>? json; }`, donde `json == null` significa borrado.
  - `class CloudSnapshot { List<CloudDoc> changes; bool fromCache; bool hasPendingWrites; }`.
  - `abstract interface class CloudWalletStore` con:
    - `Future<void> put(String box, String id, Map<String, Object?> json)`;
    - `Future<void> delete(String box, String id)`;
    - `Future<Map<String, Map<String, Map<String, Object?>>>> readAll()` (caja → id → json, solo del servidor; lanza `CloudUnavailable` sin red o con permiso denegado, indicando cuál);
    - `Future<void> uploadAll(Map<String, Map<String, Map<String, Object?>>> docs)` (lotes de 400; termina solo con la confirmación del servidor);
    - `Stream<CloudSnapshot> watch(String box)` (cambios añadidos, modificados y quitados, con metadatos);
    - `Future<DateTime?> resetAt()`;
    - `Future<void> wipe(DateTime at)` (borra por lotes todas las colecciones y escribe `resetAt`).
  - `FirestoreCloudWalletStore(FirebaseFirestore db, String uid)`. Ruta `wallets/{uid}/{box}/{id}`, con campo `json` (el mapa tal cual) y `updatedAt` (hora del servidor). La caja `settings` solo lleva las claves de `kSyncedSettings`.
  - `class CloudUnavailable implements Exception { bool permissionDenied; }`.
- **Reglas** (se añaden a las existentes):

```
    match /wallets/{uid} {
      allow read, write: if signedIn() && me() == uid;
      match /{box}/{id} {
        allow read, write: if signedIn() && me() == uid;
      }
    }
```

- [ ] **Step 1: Tests** con `FakeFirebaseFirestore`:
  - `put` y `readAll` dan ida y vuelta, incluidas fechas y mapas anidados;
  - `delete` lo quita y `watch` emite el borrado;
  - `uploadAll` con 900 documentos los sube todos;
  - `wipe` deja las colecciones vacías y fija `resetAt`;
  - un `put` de una clave de ajustes fuera de `kSyncedSettings` lanza `ArgumentError`;
  - la ruta usa el uid recibido, y otra instancia con otro uid no ve los datos.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS; `flutter test`.
- [ ] **Step 5: Commit** "Nube: almacén de la wallet por cuenta y reglas".

### Task 3: Migración y espejo en vivo

**Files:**
- Create: `lib/features/cloud/domain/migration_plan.dart`, `lib/features/cloud/presentation/cloud_sync.dart`
- Modify: `lib/app.dart` (observa `cloudSyncProvider`), `lib/features/account/presentation/session_controller.dart` (`eraseEverything` llama a `wipe` cuando la nube está disponible)
- Test: `test/migration_plan_test.dart`, `test/cloud_sync_test.dart`

**Interfaces:**
- Consumes: Task 1 y Task 2; `currentAccountProvider`; `FirebaseConfig.usable`; `authService.verifiesIdentity`; `WalletSettings.ownerUid`; `PreviewAuthService.uid`.
- Produces:
  - `bool isEffectivelyEmpty(Map<String, Map<String, Map<String, Object?>>> local)`: solo cuenta `default` sin `initialMinor` y categorías predeterminadas; ningún movimiento, suscripción ni comercio `custom.*`; ajustes ignorados.
  - `enum MigrationCase { upload, download, ask, foreign }` y `MigrationCase decideMigration({required local, required cloud, required String uid, String? localOwner})`:
    - local de otra cuenta → `foreign` (ver regla abajo);
    - local vacío → `download`;
    - nube vacía → `upload`;
    - ambos con datos → `ask`.
  - `Map<…> mergeForUpload({required local, required cloud})`: solo los ids ausentes en la nube. Para `wallet.settings`: gana la nube, salvo la unión de `deletedChargeIds`, `dismissedSplitMatchIds` y `splitAccountIds`, y `walletStartedAt` es el más antiguo. `capture.sources` se une.
  - `cloudSyncProvider` (Riverpod) y `CloudSyncState { idle, needsChoice, syncing, live, unavailable }`, más `cloudSyncStateProvider`.
  - Marca de migrado por cuenta en secure storage: `outflow.cloud.migrated.<uid>`. Se escribe solo tras `uploadAll` confirmado o tras la descarga completa.
  - Espejo en vivo tras migrar:
    - `LocalStore.changes` con `isSynced` → `put` o `delete`, sin esperar;
    - `watch(box)` → `applyRemote(Hive)` con `fromCloud`. Se ignoran los snapshots con `hasPendingWrites`, y los borrados remotos solo se aplican si `fromCache == false`.
  - `resetAt` remoto más nuevo que `outflow.cloud.loadedAt.<uid>` → `clearAll` local sin subir nada (vía `applyRemote`), y vuelve a descargar.
  - `CloudUnavailable(permissionDenied: true)` → estado `unavailable`: la app sigue en local, no hay marca, se reintenta al volver a primer plano.
  - **Otra cuenta en el teléfono (`foreign`):** lo local nunca se sube ni se muestra. Antes de descargar la wallet de la cuenta que entra, se guarda una copia de lo local en el directorio privado de documentos (`backup_<ownerUid>.json`, sin datos en logs). Luego se reemplaza lo local con `applyRemote`. Si la cuenta dueña de esa copia vuelve a entrar en este teléfono y su nube está vacía, la copia se restaura y se sube; si su nube tiene datos, se trata como `ask`.
  - `eraseEverything`: si está disponible, `wipe(now)` sin esperar, más el borrado local que ya existe; actualiza `loadedAt`.
- [ ] **Step 1: Tests**:
  - de dominio, una tabla de `decideMigration` y `mergeForUpload`, incluidas fechas y conjuntos;
  - `cloud_sync_test` con `FakeFirebaseFirestore` y Hive temporal:
    - **Review Focus 1:** un cambio remoto aplicado no genera ningún `put`;
    - **Review Focus 2:** con la nube llena y el local vacío, tras sincronizar Hive tiene los mismos documentos y `MonthSummary` y `computeBalances` coinciden;
    - **Review Focus 3:** con un almacén que lanza `permissionDenied`, el estado es `unavailable`, no hay marca y los datos siguen intactos;
    - **Review Focus 4:** local de otra cuenta → no se sube nada suyo, queda la copia `backup_*`, y al volver su dueño con la nube vacía se restaura;
    - **Review Focus 5:** con `resetAt` más nuevo, la caché local se vacía y no se sube nada;
    - una alta, un cambio y un borrado locales llegan a la nube.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS; `flutter test`.
- [ ] **Step 5: Commit** "Nube: migración una vez y espejo en vivo de la wallet".

### Task 4: Pantallas: elegir al unir, aviso y borrar

**Files:**
- Create: `lib/features/cloud/presentation/cloud_choice_sheet.dart`, `lib/features/cloud/presentation/cloud_banner.dart`
- Modify: `lib/features/home/presentation/home_screen.dart` (banner), `lib/app.dart` (abre la hoja en `needsChoice`), `lib/features/settings/presentation/settings_screen.dart` (texto de borrar y pie "Outflow · tus gastos se guardan cifrados en este teléfono" → "Tu información se guarda con tu cuenta de Google")
- Test: `test/cloud_choice_test.dart`, `test/settings_screen_test.dart`, `test/home_screen_test.dart`

**Interfaces:**
- Consumes: `cloudSyncStateProvider`, más acciones de Task 3 `chooseMerge()` y `chooseCloudOnly()` (añadirlas allí si faltan).
- Copias exactas:
  - Hoja de elegir:
    - título **Este teléfono tiene datos que no están en tu cuenta**;
    - texto "Puedes unirlos con los de tu cuenta o quedarte solo con los de la nube.";
    - botones **Unir** y **Usar solo los de la nube**;
    - confirmación del segundo: "Se descartarán los datos de este teléfono que no estén en tu cuenta. No se puede deshacer."
  - Banner `unavailable`: "Tu información aún no se está guardando en la nube", tocable para reintentar.
  - Diálogo de borrar: añade "También se borra la copia guardada en la nube."
- [ ] **Step 1: Tests**:
  - en `needsChoice` aparece la hoja; **Unir** llama a `chooseMerge`;
  - el segundo botón pide confirmar y luego llama a `chooseCloudOnly`;
  - en `unavailable` se ve el banner en Inicio, y en `live` no;
  - el diálogo de borrar incluye el texto nuevo; a 360 px no hay desbordes.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS; `flutter test`, `flutter build apk --debug`.
- [ ] **Step 5: Commit** "Nube: elegir al unir, aviso sin guardar y borrar también en la nube".

### Después (con el usuario)
- Publicar `firestore.rules` en la consola. Sin eso se ve el aviso y la app sigue en local.
- Actualizar primero en un teléfono y luego en el otro, eligiendo **Unir**.
