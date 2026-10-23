# Outflow 2 · Fase 4 (Amigos y dividir gastos) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Añadir amigos por correo, dividir gastos con ellos (iguales, por importes o por productos del ticket) y ver quién debe a quién, contando en la wallet solo tu parte.

**Architecture:** Dominio en Dart puro (gasto compartido, reparto, saldos, conciliación con la wallet). Un único `SocialRepository` (Firestore con caché local; uno "no disponible" en vista previa/web/tests sin Firebase) alimenta providers de Riverpod. Igual que los cobros de suscripciones, un provider concilia los gastos compartidos con movimientos locales `origin: split` (id `split:<expenseId>`, importe = tu parte). La UI: 5.ª pestaña Amigos, editor de división y tarjeta de saldos en Inicio.

**Tech Stack:** Flutter 3.47.7, Riverpod 3, `cloud_firestore: 6.0.0` (fijo: casa con `firebase_core 4.0.0` / `firebase_auth 6.0.0`; no subir), `fake_cloud_firestore` (dev, la versión que resuelva `flutter pub add dev:fake_cloud_firestore`).

**Spec:** `docs/superpowers/specs/2026-10-22-outflow-fases-2-3-4-design.md` (sección Fase 4 y "Decisiones tomadas por Claude")

## Global Constraints
- **Decisión B:** en tu wallet solo cuenta tu parte (gasto `origin: split`). Saldar **no** crea ingresos ni gastos.
- Un amigo solo ve los gastos compartidos en los que participa y tu perfil mínimo (nombre, correo, foto). Nada más de tu wallet sale del teléfono.
- Sin red: todo se lee de la caché y las escrituras se encolan (persistencia por defecto de Firestore). Sin avisos push.
- Sin Firebase (web, vista previa, build sin secretos): la pestaña Amigos muestra "Entra con tu cuenta de Google para dividir gastos con amigos." y nada falla.
- Dinero en unidades menores (`int`); el reparto siempre suma exactamente el total.
- Interfaz en español, estilo y animaciones de la fase 1 (`Entrance`, `Pressable`, `SheetScaffold`, `AppMotion.reduced`).
- `flutter analyze` limpio y `flutter test` verde en cada tarea; commits con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus
1. Abrir la app sin red y con la caché vacía (o primera lectura desde caché) → **no** se borran los gastos `split` locales; solo se borran con datos del servidor. → test Task 2.
2. S/ 100 entre 3 → 33.34 + 33.33 + 33.33 (suma exacta); productos que no suman el total (propina, IGV) → la diferencia se reparte en proporción. → test Task 1.
3. Añadir amigo con su propio correo, en mayúsculas/espacios, alguien que ya te había invitado, o sin red → mensaje claro (y aceptación automática en el caso cruzado). → test Task 3.
4. Un participante que no es el creador intenta editar el gasto → solo puede marcar pagos; en el teléfono no ve "Editar"/"Borrar"; las reglas lo impiden en el servidor. → test Task 3 (repo) y Task 4 (UI).
5. Dividir un gasto ya registrado con Apple/Google Pay → "¿Es este pago?" y, si sí, ese gasto se reemplaza por tu parte (no se cuenta dos veces). → test Task 5.

---

### Task 1: Dominio de gastos compartidos, reparto y saldos

**Files:**
- Create: `lib/features/friends/domain/shared_expense.dart`, `lib/features/friends/domain/split_math.dart`, `lib/features/friends/domain/balances.dart`
- Test: `test/split_math_test.dart`, `test/balances_test.dart`

**Interfaces:**
- Produces:
  - `class Person { String uid; String name; String email; String? photoUrl; String get firstName; toJson/fromJson }`
  - `enum SplitMode { equal, amounts, items }`
  - `class SplitItem { String name; int amountMinor; List<String> uids; }`
  - `class Settlement { String by; DateTime at; }`
  - `class SharedExpense { String id; String createdBy; String paidBy; List<String> participants; Map<String, Person> people; String title; DateTime date; String currency; int totalMinor; String categoryId; SplitMode mode; Map<String, int> shares; List<SplitItem> items; Map<String, Settlement> settled; DateTime updatedAt; }` con `copyWith`, `toJson`/`fromJson` (fechas ISO‑8601), `int shareOf(String uid)` (0 si no participa), `bool isSettled(String debtorUid)`, `Iterable<String> debtors` (participantes ≠ `paidBy` con parte > 0). `settled` va por deudor.
  - `Map<String, int> splitEqually(int totalMinor, List<String> uids)`: los céntimos sobrantes van a los primeros de la lista.
  - `Map<String, int> splitByItems(List<SplitItem> items, int totalMinor)`: cada producto se reparte a partes iguales entre sus `uids`; si la suma de productos ≠ total, la diferencia se reparte en proporción a lo ya asignado (método del mayor resto). Lanza `ArgumentError` si algún producto no tiene personas.
  - `String? validateShares(Map<String, int> shares, int totalMinor)`: null si es válido, si no el texto `'Faltan S/ 4.00 por repartir'` o `'Sobran S/ 4.00'` (formateado con `Fmt.money` y la moneda que reciba como parámetro `currency`).
  - `class Balance { String friendUid; Map<String, int> byCurrency; }` (positivo = te debe; negativo = le debes) y `List<Balance> computeBalances(List<SharedExpense> expenses, String myUid)` — solo deudas no saldadas en las que estás tú; amigos con todo a 0 no aparecen.
  - `({Map<String, int> owedToMe, Map<String, int> iOwe}) totalsByCurrency(List<Balance> balances)`.

- [ ] **Step 1: Tests** — `splitEqually(10000, [a,b,c])` → `{a:3334, b:3333, c:3333}`; `splitEqually(100, [a])` → `{a:100}`. `splitByItems`: pizza 6000 entre a,b y cerveza 2000 solo b, total 8000 → `{a:3000, b:5000}`; mismo con total 8800 (propina) → `{a:3300, b:5500}` y suma 8800; producto sin uids → `ArgumentError`. `validateShares({a:5000,b:4600}, 10000, currency:'PEN')` → contiene `'Faltan'`; suma exacta → null. `computeBalances`: pagué 10000 entre yo/ana/javi a partes iguales → ana +3333, javi +3333; ana pagó 3000 entre ella y yo → ana −1500 (neto ana +1833); con `settled['javi']` → javi no aparece; dos monedas → dos entradas en `byCurrency`. `SharedExpense.fromJson(e.toJson())` == campos iguales.
- [ ] **Step 2: Run** `flutter test test/split_math_test.dart test/balances_test.dart` → FAIL (no existen).
- [ ] **Step 3: Implement** los tres archivos.
- [ ] **Step 4: Run** de nuevo → PASS; `flutter analyze` limpio.
- [ ] **Step 5: Commit** "Amigos: dominio de gastos compartidos y saldos".

### Task 2: Tu parte en la wallet

**Files:**
- Create: `lib/features/friends/domain/split_movements.dart`
- Modify: `lib/features/wallet/presentation/wallet_providers.dart` (`WalletActions.delete` no borra `origin: split`: devuelve null), `lib/features/wallet/presentation/widgets/movement_sheet.dart` (al editar un `split`: solo categoría y nota editables, sin botón de borrar, aviso "Gasto compartido · se edita en Amigos"), `lib/app.dart` (`ref.watch(splitMovementSyncProvider)` junto a `chargeMovementSyncProvider`)
- Test: `test/split_movements_test.dart`, `test/movement_sheet_test.dart`

**Interfaces:**
- Consumes: `SharedExpense`, `shareOf` (Task 1); `socialRepositoryProvider`/`sharedExpensesProvider` (Task 3; en esta tarea el provider de sync se declara en `lib/features/friends/presentation/friends_providers.dart` y lee `sharedExpensesProvider`, que la Task 3 rellena; aquí basta con declararlo como `StreamProvider<ExpensesSnapshot>` que emite `ExpensesSnapshot(const [], fromCache: true)`).
- Produces:
  - `class ExpensesSnapshot { List<SharedExpense> expenses; bool fromCache; }`
  - `String splitMovementId(String expenseId)` → `'split:$expenseId'`.
  - `({List<Movement> upsert, List<String> delete}) reconcileSplitMovements({required ExpensesSnapshot snapshot, required List<Movement> existing, required String myUid, required Set<String> categoryIds})`: por cada gasto donde `shareOf(myUid) > 0` → gasto `kind: expense`, `origin: split`, importe = tu parte en la moneda del gasto, título y fecha del gasto, nota `'Dividido con Ana, Javi · total S/ 100.00'`; categoría: la del movimiento existente si ya existe (el usuario pudo cambiarla), si no la del gasto si está en `categoryIds`, si no `'expense_other'`. Solo emite cambios reales (idempotente). **Borra** movimientos `split` sin gasto (o con parte 0) **solo si `fromCache == false`**.
  - `final splitMovementSyncProvider = Provider<void>(...)` (patrón de `chargeMovementSyncProvider`; no hace nada sin cuenta).

- [ ] **Step 1: Tests** — gasto nuevo → 1 upsert con id `split:e1`, importe 3333, `origin: split`; segunda pasada con ese movimiento → sin cambios; el gasto cambia de título → upsert conservando la categoría que eligió el usuario; gasto ausente con `fromCache: true` → sin borrados; con `fromCache: false` → borra `split:e1`; movimientos manuales nunca se tocan. Hoja de gasto con un `split`: no hay "Borrar" y el importe no es editable.
- [ ] **Step 2: Run** `flutter test test/split_movements_test.dart test/movement_sheet_test.dart` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS; `flutter test` completo verde.
- [ ] **Step 5: Commit** "Amigos: tu parte de cada gasto compartido en la wallet".

### Task 3: Firestore (perfiles, amigos, gastos) y reglas

**Files:**
- Create: `lib/features/friends/data/social_repository.dart` (interfaz + `UnavailableSocialRepository`), `lib/features/friends/data/firestore_social_repository.dart`, `firestore.rules` (raíz del repo)
- Modify: `pubspec.yaml` (`cloud_firestore: 6.0.0`, dev `fake_cloud_firestore`), `lib/features/friends/presentation/friends_providers.dart`, `lib/app.dart` (publica el perfil al pasar a `Ready`), `.github/workflows/ios-unsigned.yml` (`timeout-minutes: 60`: Firestore por SPM compila más)
- Test: `test/firestore_social_repository_test.dart`

**Interfaces:**
- Consumes: `Account` (`uid`, `email`, `displayName`, `photoUrl`); tipos de Task 1; `ExpensesSnapshot` (Task 2).
- Produces:
  - `enum AddFriendResult { sent, accepted, notOnOutflow, self, alreadyFriends, alreadySent, offline }`
  - `class FriendRequest { String id; Person from; Person to; }`
  - `abstract interface class SocialRepository { bool get available; Future<void> publishProfile(Account me); Stream<List<Person>> watchFriends(); Stream<List<FriendRequest>> watchIncoming(); Stream<List<FriendRequest>> watchOutgoing(); Future<AddFriendResult> addFriend(String email); Future<void> answer(String requestId, {required bool accept}); Stream<ExpensesSnapshot> watchExpenses(); Future<void> saveExpense(SharedExpense e); Future<void> deleteExpense(String id); Future<void> settle(String expenseId, String debtorUid); }` — `UnavailableSocialRepository`: `available == false`, streams vacíos, escrituras lanzan `StateError`.
  - `FirestoreSocialRepository(FirebaseFirestore db, String myUid)`.
  - Providers: `socialRepositoryProvider` (Firestore solo si `!kIsWeb && FirebaseConfig.isConfigured && authService.verifiesIdentity` y hay `currentAccountProvider`; si no, Unavailable), `friendsProvider`, `incomingRequestsProvider`, `outgoingRequestsProvider`, `sharedExpensesProvider` (`StreamProvider<ExpensesSnapshot>`), `balancesProvider` (`computeBalances`).
- **Modelo de documentos:**
  - `users/{uid}`: `{name, email (minúsculas, sin espacios), photoUrl, updatedAt}`.
  - `friendRequests/{fromUid}_{toUid}`: `{from, to, fromPerson, toPerson, status: 'pending'|'accepted', createdAt}`. Amistad = documento `accepted` en cualquier sentido; rechazar = borrar el documento.
  - `expenses/{id}`: `SharedExpense.toJson()` (incluye `participants` para las consultas `arrayContains`).
- **`addFriend(email)`:** normaliza; tu correo → `self`; busca `users` por `email` con `limit(1)` desde servidor (error de red / `isFromCache` → `offline`); sin resultado → `notOnOutflow`; existe doc `accepted` en algún sentido → `alreadyFriends`; existe `{yo}_{él}` pending → `alreadySent`; existe `{él}_{yo}` pending → lo acepta → `accepted`; si no, crea `{yo}_{él}` → `sent`.
- **`settle`:** escribe solo `settled.<debtor>` = `{by: myUid, at}` y `updatedAt`.
- **`firestore.rules` (texto exacto a pegar en la consola):**

```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    function signedIn() { return request.auth != null; }
    function me() { return request.auth.uid; }

    match /users/{uid} {
      allow get: if signedIn();
      allow list: if signedIn() && request.query.limit <= 1;
      allow write: if signedIn() && me() == uid;
    }

    match /friendRequests/{id} {
      allow read: if signedIn() && me() in [resource.data.from, resource.data.to];
      allow create: if signedIn() && request.resource.data.from == me()
        && id == me() + '_' + request.resource.data.to
        && request.resource.data.status == 'pending';
      allow update: if signedIn() && me() == resource.data.to
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status'])
        && request.resource.data.status == 'accepted';
      allow delete: if signedIn() && me() in [resource.data.from, resource.data.to];
    }

    match /expenses/{id} {
      allow read: if signedIn() && me() in resource.data.participants;
      allow create: if signedIn() && request.resource.data.createdBy == me()
        && me() in request.resource.data.participants;
      allow update: if signedIn() && (
        (me() == resource.data.createdBy && request.resource.data.createdBy == me())
        || (me() in resource.data.participants
            && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['settled', 'updatedAt'])));
      allow delete: if signedIn() && me() == resource.data.createdBy;
    }
  }
}
```

- [ ] **Step 1: Tests** (`FakeFirebaseFirestore`) — `publishProfile` guarda `email` en minúsculas; `addFriend(' ANA@Mail.com ')` con Ana publicada → `sent` y existe `me_ana`; repetirlo → `alreadySent`; correo desconocido → `notOnOutflow`; el tuyo → `self`; Ana ya te invitó (`ana_me` pending) → `accepted` y `watchFriends()` emite Ana para los dos; `answer(id, accept:false)` borra la solicitud; `saveExpense` + `watchExpenses()` lo emite solo a participantes (repo de un tercero no lo ve); `settle('e1','ana')` cambia solo `settled.ana`; `deleteExpense` lo quita del stream.
- [ ] **Step 2: Run** `flutter test test/firestore_social_repository_test.dart` → FAIL.
- [ ] **Step 3: Implement** (añadir dependencias con `flutter pub add cloud_firestore:6.0.0` y `flutter pub add dev:fake_cloud_firestore`; si la resolución choca con `firebase_core 4.0.0`, fijar la versión de `fake_cloud_firestore` que acepte `cloud_firestore 6.0.0`).
- [ ] **Step 4: Run** → PASS; `flutter test` completo; `flutter build apk --debug` compila (Firestore en Android).
- [ ] **Step 5: Commit** "Amigos: Firestore, solicitudes de amistad y reglas".

### Task 4: Pestaña Amigos, saldos y saldar

**Files:**
- Create: `lib/features/friends/presentation/friends_screen.dart`, `friend_detail_screen.dart`, `add_friend_sheet.dart`, `debts_card.dart` (todos en `lib/features/friends/presentation/`)
- Modify: `lib/features/shell/presentation/glass_tab_bar.dart` (`AppTab.friends('Amigos', LucideIcons.users)` entre `subscriptions` y `summary`; con 5 pestañas la etiqueta va en `FittedBox(fit: BoxFit.scaleDown)` para que "Suscripciones" no se corte), `lib/app.dart` (página de la pestaña), `lib/features/home/presentation/home_screen.dart` (`DebtsCard` bajo `WalletCard`), `test/support/fakes.dart` (`MemorySocial implements SocialRepository`)
- Test: `test/friends_screen_test.dart`, `test/app_shell_test.dart`, `test/home_screen_test.dart`

**Interfaces:**
- Consumes: providers de Task 3, `computeBalances`/`totalsByCurrency` (Task 1), `showSplitEditor` (Task 5; aquí el "+" puede llamar a una función que la Task 5 completa — en esta tarea solo "Añadir amigo").
- Produces: `FriendsScreen`, `FriendDetailScreen(friendUid)`, `showAddFriendSheet(BuildContext)`, `DebtsCard`.
- **Pantalla Amigos:** sin repo disponible → texto de Global Constraints. Si no: arriba "Te deben S/ 75 · Debes S/ 12" (por moneda); "Solicitudes" (entrantes con **Aceptar**/**Rechazar**, salientes con "Pendiente"); lista de amigos con su saldo ("Te debe S/ 25", "Le debes S/ 12", "Al día"); "Gastos compartidos" (historial, más reciente primero). Botón "+" en la cabecera → menú: **Añadir amigo**, **Dividir un gasto**. Vacío: "Añade a tus amigos por su correo de Google."
- **Añadir amigo:** campo de correo + **Enviar solicitud**; textos por resultado: `sent` "Solicitud enviada.", `accepted` "Ya te había invitado: ahora son amigos.", `notOnOutflow` "Esa persona aún no usa Outflow. Pídele que la instale y entre con Google.", `self` "Ese es tu correo.", `alreadyFriends` "Ya son amigos.", `alreadySent` "Ya le enviaste una solicitud.", `offline` "Sin conexión".
- **Detalle de amigo:** saldo, **Saldar todo** (confirmación; marca `settle` en cada gasto pendiente entre los dos, en ambos sentidos), lista de gastos con "Tu parte", quién pagó y estado ("Pendiente"/"Pagado"); tocar uno → hoja con **Marcar como pagado** y, solo si `createdBy == yo`, **Editar** y **Borrar**.
- **DebtsCard:** solo si hay saldos ≠ 0; toca → pestaña Amigos (`ShellScope.select(AppTab.friends)`).

- [ ] **Step 1: Tests** (con `MemorySocial`) — sin repo disponible se ve el texto de "Entra con tu cuenta de Google…"; solicitud entrante → **Aceptar** la convierte en amigo; añadir `nadie@x.com` muestra el texto de `notOnOutflow`; amigo con gasto pendiente muestra "Te debe S/ 33.33"; **Saldar todo** → "Al día" y la wallet no gana movimientos; gasto creado por otro → sin "Editar"/"Borrar"; la barra tiene 5 pestañas sin overflow a 360 px de ancho; Inicio muestra "Te deben" con saldo y no lo muestra sin saldo.
- [ ] **Step 2: Run** `flutter test test/friends_screen_test.dart test/app_shell_test.dart test/home_screen_test.dart` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS; `flutter test` completo verde.
- [ ] **Step 5: Commit** "Amigos: pestaña, saldos y saldar".

### Task 5: Dividir un gasto (editor y entradas)

**Files:**
- Create: `lib/features/friends/presentation/split_editor_screen.dart`, `lib/features/wallet/presentation/widgets/match_payment_sheet.dart` (se extrae de `receipt_result_screen.dart` el "¿Es este pago?")
- Modify: `lib/features/wallet/presentation/widgets/movement_sheet.dart` (interruptor **Dividir con amigos** en gasto nuevo, visible solo si el repo está disponible: al guardar abre el editor con importe, concepto, fecha y categoría en lugar de guardar el gasto), `lib/features/receipts/presentation/receipt_result_screen.dart` (botón **Dividir con amigos** activo si el repo está disponible, con los productos), `friends_screen.dart` ("Dividir un gasto")
- Test: `test/split_editor_test.dart`, `test/receipt_result_test.dart`

**Interfaces:**
- Consumes: Task 1 (`splitEqually`, `splitByItems`, `validateShares`), Task 3 (`saveExpense`, `deleteExpense`, `friendsProvider`), `findMatchingPayments` (fase 3), `ReceiptItem`.
- Produces:
  - `class SplitDraft { int totalMinor; String currency; String title; DateTime date; String categoryId; List<ReceiptItem> items; String? sourceMovementId; }`
  - `Future<void> showSplitEditor(BuildContext context, {SplitDraft? draft, SharedExpense? editing})`
  - `Future<(bool decided, Movement? chosen)> askMatchingPayment(BuildContext context, List<Movement> candidates)`
- **Editor:** importe (`AmountKeypad`), concepto, fecha; **Pagó** (chips: "Tú" + amigos, uno); **Entre** (multiselección, "Tú" marcado por defecto); modo `SegmentedControl` **Iguales / Importes / Productos** (Productos solo con productos): en Importes un campo por persona y el aviso de `validateShares`; en Productos, por cada producto chips con las personas (tocar alterna). Pie: "Tu parte: S/ 25.00". **Guardar** activo con ≥ 2 participantes y reparto válido. Al guardar un gasto nuevo sin `sourceMovementId`, busca `findMatchingPayments` (importe ±1 % o comercio, 3 días, sin contar `split`) y pregunta con `askMatchingPayment`; si eligió uno, guarda el gasto compartido y **borra** ese movimiento (la sincronización crea tu parte). Editando (solo creador): mismo formulario + **Borrar gasto compartido**. El id nuevo es `Uuid().v4()`; `people` lleva el `Person` de cada participante.

- [ ] **Step 1: Tests** (con `MemorySocial` y `MemoryMovements`) — 100 entre yo y Ana a partes iguales → `saveExpense` con `shares {yo:5000, ana:5000}` y `paidBy: yo`; modo Importes 60/30 sobre 100 → Guardar deshabilitado y "Faltan S/ 10.00"; modo Productos desde un ticket con 2 productos asignados → `shares` de `splitByItems`; existe un gasto Google Pay de 100 hace 1 h → "¿Es este pago?" → elegirlo lo borra de la wallet y guarda el compartido; "No, es otro" no borra nada; la hoja de gasto con el interruptor abre el editor con el importe escrito y no guarda un gasto manual; resultado de ticket → **Dividir con amigos** abre el editor con los productos.
- [ ] **Step 2: Run** `flutter test test/split_editor_test.dart test/receipt_result_test.dart` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS; `flutter test` completo verde; `flutter analyze` limpio.
- [ ] **Step 5: Commit** "Amigos: dividir gastos".

### Después de la Task 5 (con el usuario)
- Guía para el usuario: activar **Firestore** en la consola (modo producción, región `southamerica-east1` o la más cercana), pegar `firestore.rules` en **Reglas → Publicar**.
- Push a `outflow-2` → APK de Actions; prueba real con un amigo con Android: añadirse, dividir, saldar, y abrir sin red.
