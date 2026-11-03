# Outflow · Wallet con dinero real Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que la wallet refleje dinero real: cuentas con saldo, transferencias y ajustes, captura automática "por revisar", importación de estados de cuenta desde Ajustes y sesión única por cuenta de Google.

**Architecture:** El dominio sigue en Dart puro. `Movement` gana cuenta, tipos `transfer`/`adjustment` y separa lo que cuenta en el Resumen (`countsInWallet`) de lo que mueve la cuenta (`accountEffectMinor`). Todas las fuentes de captura dejan texto en una bandeja JSONL (`capture_inbox.jsonl`) que Dart procesa al abrir con un único lector (`parseBankText`). La sesión única usa `sessions/{uid}` en Firestore; la wallet nunca sale del teléfono.

**Tech Stack:** Flutter 3.47.7, Riverpod 3, Hive CE, Firestore 6.0.0 (firebase pins intactos), `file_picker` (ya está), `spreadsheet_decoder` (xlsx), PDF nativo propio: PDFKit en iOS y `com.tom-roush:pdfbox-android` en Android por el canal `outflow/pdf` (sin licencias de pago).

**Spec:** `docs/superpowers/specs/2026-11-03-wallet-real-design.md`

## Global Constraints
- La wallet (movimientos, cuentas, saldos) **no sale del teléfono**; a Firestore solo va `sessions/{uid}`.
- Nunca se piden claves bancarias ni se conecta con agregadores ni con la API de Gmail.
- Correos, avisos y SMS bancarios se interpretan **solo en el teléfono**, nunca con IA.
- Los cobros de suscripción (`origin: subscription`) se ven pero no cuentan ni mueven cuentas.
- Decisión B vigente: en Resumen y "Te queda" solo cuenta tu parte de un gasto compartido.
- Transferencias y ajustes no cuentan en gastos, ingresos, categorías ni "Te queda".
- "Por revisar" cuenta en todos los números y se distingue a la vista.
- Si el lector no reconoce un importe, no crea nada.
- Dinero en unidades menores; importes de `Movement.amount` siempre positivos.
- Datos antiguos se leen sin reescribirse: campos nuevos opcionales; `accountId == null` = cuenta por defecto.
- Interfaz en español, estilo y animaciones actuales. `flutter analyze` limpio y `flutter test` verde por tarea; commits con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. El código Swift solo se compila en CI.

## Review Focus
1. Actualizar la app con datos existentes → "Te queda" y el historial no cambian, nace "Mi cuenta" y solo una aunque arranque dos veces. → test Task 2.
2. Mismo pago por dos vías (aviso y correo, o captura e importación) → un solo movimiento. → tests Task 4 y Task 7.
3. Enlace `outflow://captura` abierto por otra app o web sin la clave → se ignora, no crea movimientos. → test Task 6.
4. Sesión cerrada por otro dispositivo sin red o con escritura pendiente → no cierra por datos de caché ni por su propia escritura pendiente; la wallet local sigue intacta. → test Task 1.
5. Importe con formato peruano ("S/ 1,250.50", "1.250,50", "PEN 45"), o texto con varios importes (saldo disponible, comisión) → toma el importe de la operación, no el saldo. → test Task 4.

---

### Task 1: Sesión única por cuenta

**Files:**
- Create: `lib/features/account/data/device_session.dart`
- Modify: `lib/features/account/presentation/session_controller.dart`, `lib/features/account/presentation/welcome_screen.dart`, `lib/app.dart`, `firestore.rules`
- Test: `test/device_session_test.dart`, `test/session_controller_test.dart`

**Interfaces:**
- Produces:
  - `class RemoteDevice { String? deviceId; bool trusted; }` (`trusted` = ni de caché ni con escrituras pendientes).
  - `abstract interface class DeviceSessionRepository { Future<void> claim(String uid, String deviceId); Stream<RemoteDevice> watch(String uid); }`, `FirestoreDeviceSessionRepository(FirebaseFirestore db)` (`sessions/{uid}` = `{deviceId, platform, updatedAt}`, con `includeMetadataChanges: true`), `NoDeviceSessionRepository` (sin Firebase: no hace nada, sin emitir).
  - `bool isSessionLost(RemoteDevice remote, String myDeviceId)`: true solo si `trusted`, `deviceId != null` y distinto.
  - `deviceIdProvider`: id aleatorio (`Uuid`) en secure storage bajo `outflow.device.id`.
  - `SignedOut({String? notice})`; `SessionController.sessionLost()` hace `_auth.signOut()` y pasa a `SignedOut(notice: 'Tu cuenta se abrió en otro dispositivo.')` sin tocar datos locales.
  - `deviceSessionGuardProvider` (observado en `app.dart`): con cuenta real, si el documento no existe reclama (usuarios que actualizan); si `isSessionLost`, llama a `sessionLost()`.
- `continueWithGoogle` reclama tras entrar bien, sin esperar al servidor. Face ID no reclama.
- Reglas: `match /sessions/{uid} { allow read, write: if signedIn() && me() == uid; }`.

- [ ] **Step 1: Tests** — `isSessionLost`: otro id y `trusted` → true; otro id con `trusted:false` → false; mismo id o null → false. Con repositorio falso: guard con documento ausente reclama una vez; otro dispositivo → estado `SignedOut` con el aviso, wallet (`MemoryMovements`, ajustes) intacta y `auth.current == null`; `continueWithGoogle` llama a `claim` y se queda en sesión aunque `claim` nunca termine; desbloquear con Face ID no reclama; bienvenida muestra `notice`.
- [ ] **Step 2: Run** `flutter test test/device_session_test.dart test/session_controller_test.dart` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS; `flutter test` completo.
- [ ] **Step 5: Commit** "Sesión única: el último dispositivo cierra los demás".

### Task 2: Cuentas, transferencias y ajustes (dominio y datos)

**Files:**
- Create: `lib/features/wallet/domain/wallet_account.dart`, `lib/features/wallet/domain/account_balances.dart`, `lib/features/wallet/data/hive_account_repository.dart`
- Modify: `lib/features/wallet/domain/movement.dart`, `lib/features/wallet/domain/month_summary.dart`, `lib/features/wallet/presentation/wallet_providers.dart`, `lib/core/storage/local_store.dart` (caja `accounts`, también en `openUnencrypted`), `lib/features/account/presentation/session_controller.dart` (`eraseEverything` deja `Mi cuenta`), `lib/features/wallet/presentation/screens/movements_screen.dart`, `test/support/fakes.dart` (`MemoryAccounts`)
- Test: `test/account_balances_test.dart`, `test/month_summary_test.dart`, `test/wallet_data_test.dart`

**Interfaces:**
- Produces:
  - `enum AccountType { bank, wallet, cash, creditCard, other }`; `class WalletAccount { String id; String name; AccountType type; String currency; int initialMinor; DateTime initialDate; String? lastDigits; bool isDefault; bool archived; toJson/fromJson; copyWith }`.
  - `Movement`: `MovementKind.transfer`, `MovementKind.adjustment`; `MovementOrigin.settlement`, `capture`, `import`; campos `String? accountId`, `String? toAccountId`, `int? receivedMinor`, `int? adjustmentMinor` (con signo), `int? paidMinor` (lo que salió de verdad; null = `amount`), `bool needsReview`, `String? externalRef`.
  - `countsInWallet`: false para `origin: subscription`, `settlement` y para `transfer`/`adjustment`.
  - `int accountEffectMinor(Movement m, String accountId, String defaultAccountId)`: 0 si `subscription`; ingreso `+amount`; gasto `-(paidMinor ?? amount)`; ajuste `adjustmentMinor`; transferencia `-amount` en origen y `+(receivedMinor ?? amount)` en destino; `accountId == null` equivale a `defaultAccountId`; 0 si no es de esa cuenta. Una cuenta solo cuenta movimientos en su moneda (destino de transferencia exento).
  - `Map<String, int> computeBalances(List<WalletAccount>, List<Movement>)` → saldo por cuenta; `Map<String,int> totalsByCurrency`.
  - `Movement makeAdjustment({required WalletAccount account, required int currentMinor, required int realMinor, required DateTime now})`, null si no hay diferencia; `Movement makeTransfer({from, to, amountMinor, receivedMinor?, date, note})`.
  - `abstract interface class AccountRepository { Stream<List<WalletAccount>> watchAll(); Future<void> save(WalletAccount); Future<void> delete(String id); Future<WalletAccount> ensureDefault(String currency); }`; `ensureDefault` crea "Mi cuenta" (`initialMinor: 0`) solo si no hay ninguna y es idempotente. Providers `accountRepositoryProvider`, `accountsProvider`, `accountBalancesProvider`, `defaultAccountProvider`.
- Una cuenta con movimientos no se borra: se archiva. La por defecto no se puede archivar.
- `suggestCategory`, `findMatchingPayments`, `findRecentDuplicate`, `_dayTotal` y la lista de Movimientos ignoran transferencias y ajustes donde corresponda; `category` puede ser null en esos tipos sin romper `MovementRow`, que los muestra con su propio icono ("BCP → Dale", "Ajuste de saldo").

- [ ] **Step 1: Tests** — transferencia de 10000 de A a B: A −10000, B +10000; `MonthSummary` no cambia. Entre monedas con `receivedMinor`. Ajuste: saldo 5000, real 4200 → `adjustmentMinor: -800`, no cambia `remaining`; real = actual → null. Gasto con `paidMinor: 10000` y `amount: 2500`: Resumen 2500, cuenta −10000. Movimiento antiguo sin `accountId` afecta a la cuenta por defecto y JSON antiguo se lee igual. Suscripción: efecto 0. **Review Focus 1:** `ensureDefault` dos veces deja una; `MonthSummary` idéntico con los mismos datos antes y después.
- [ ] **Step 2: Run** los tres archivos → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS; `flutter test` completo.
- [ ] **Step 5: Commit** "Cuentas: saldos, transferencias y ajustes".

### Task 3: Cuentas en la interfaz

**Files:**
- Create: `lib/features/wallet/presentation/screens/accounts_screen.dart` (lista y detalle), `lib/features/wallet/presentation/widgets/account_editor_sheet.dart`, `lib/features/wallet/presentation/widgets/transfer_sheet.dart`, `lib/features/wallet/presentation/widgets/accounts_card.dart`, `lib/features/wallet/presentation/widgets/account_picker.dart`
- Modify: `lib/features/home/presentation/home_screen.dart`, `lib/features/wallet/presentation/widgets/movement_sheet.dart`, `lib/features/receipts/presentation/receipt_result_screen.dart`, `lib/features/shell/presentation/quick_add_menu.dart` (acción `transfer` "Transferencia"), `lib/app.dart`, `lib/features/onboarding/presentation/onboarding_controller.dart`, `lib/features/onboarding/presentation/onboarding_steps.dart`, `lib/features/settings/presentation/settings_screen.dart` (fila "Cuentas")
- Test: `test/accounts_screen_test.dart`, `test/movement_sheet_test.dart`, `test/onboarding_controller_test.dart`, `test/home_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 completa.
- Produces: `AccountsCard` (bajo `WalletCard`, título **Saldo en cuentas**, total en moneda principal, otras monedas aparte, toca → `AccountsScreen`); `showAccountEditor(context, {WalletAccount? editing})`; `showTransferSheet(context)`; `AccountPicker(selectedId, onChanged)`.
- Copias exactas: **Mi saldo real es…**, **Saldo en cuentas**, **Transferencia**, **Ajuste de saldo**, **Tu primera cuenta**. Sugerencias del editor: BCP, BBVA, Interbank, Scotiabank, Dale, Yape, Plin, Efectivo; texto libre.
- Hoja de gasto y resultado de ticket: `AccountPicker` que empieza en la por defecto (solo si hay más de una cuenta). Editar un `subscription` no lo muestra.
- Onboarding: el paso de saldo inicial pasa a **Tu primera cuenta** (nombre + saldo): crea la cuenta con `initialMinor` y **no** crea el movimiento "Saldo inicial". `short` (quien ya tenía datos) no lo muestra.

- [ ] **Step 1: Tests** — crear cuenta y verla en Inicio con su saldo; "Mi saldo real es…" crea ajuste y el saldo queda en ese valor; "Te queda" no cambia; transferencia desde "+" sin cuentas suficientes pide crear otra; gasto con cuenta elegida baja esa cuenta; onboarding crea la cuenta sin movimiento "Saldo inicial"; sin datos a 360 px no desborda.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS; `flutter test`.
- [ ] **Step 5: Commit** "Cuentas: pantallas, Inicio, transferencias y primer paso".

### Task 4: Lector de texto, bandeja y revisión

**Files:**
- Create: `lib/features/capture/domain/parse_bank_text.dart`, `lib/features/capture/domain/process_captures.dart`, `lib/features/capture/data/capture_inbox.dart`, `lib/features/capture/data/capture_sources_repository.dart`, `lib/features/capture/presentation/capture_providers.dart`, `lib/features/capture/presentation/review_card.dart`, `lib/features/capture/presentation/review_screen.dart`
- Modify: `lib/app.dart`, `lib/features/home/presentation/home_screen.dart`, `lib/features/wallet/presentation/widgets/movement_row.dart`, `lib/features/account/presentation/session_controller.dart`
- Test: `test/parse_bank_text_test.dart`, `test/process_captures_test.dart`, `test/review_screen_test.dart`

**Interfaces:**
- Consumes: `parseAmountMinor`, `normalizeMerchant`, `suggestCategory`, `WalletAccount`, `Movement`.
- Produces:
  - `enum CaptureDirection { out, inbound }`; `class ParsedBankText { int amountMinor; String currency; CaptureDirection direction; String? counterparty; DateTime? date; String? operationId; String? accountDigits; bool isTransfer; }`; `ParsedBankText? parseBankText(String text, {required String fallbackCurrency, required DateTime now})`. Prefiere el importe junto a "monto/importe/pagaste/enviaste/recibiste/transferiste"; descarta "saldo", "disponible", "comisión", "ITF"; sentido por verbos; null sin importe.
  - `class CaptureEvent { String sourceKey; String sourceLabel; String text; DateTime receivedAt; String? imageOperationId; toJson/fromJson }`; `CaptureInbox { Future<void> add(CaptureEvent); Future<List<CaptureEvent>> drain(); Future<void> clear(); }` sobre `capture_inbox.jsonl` en `getApplicationDocumentsDirectory()`, mismo patrón que `ChargeAnswerInbox`.
  - `class CaptureOutcome { List<Movement> upsert; List<CaptureEvent> unmatchedSources; }`; `CaptureOutcome processCaptures({events, accounts, movements, Map<String,String> sourceAccounts, categories, defaultAccountId, now})`: cuenta por dígitos → nombre en el texto → fuente → por defecto. Duplicado (`externalRef` igual, o mismo importe y sentido en la misma cuenta en ±2 días con comercio compatible o vacío): completa el existente; con duda crea con nota "¿duplicado?". Transferencia solo si reconoce destino propio. Movimiento: `origin: capture`, `needsReview: true`, `externalRef`.
  - `captureSyncProvider` (observado en `app.dart`): en `Ready` y al volver a primer plano procesa la bandeja una vez. `CaptureSourcesRepository`: `Map` fuente→cuenta en caja `settings`.
- `ReviewCard` en Inicio: **N movimientos por revisar** → `ReviewScreen`: confirmar, editar (hoja de gasto, con opción de convertir en transferencia) o borrar. "Por revisar" se marca en `MovementRow`. `eraseEverything` llama a `CaptureInbox.clear()`.

- [ ] **Step 1: Tests** — **Review Focus 5:** "S/ 1,250.50", "1.250,50", "PEN 45"; "Pagaste S/ 25.00… saldo disponible S/ 900.00" → 2500; "Comisión S/ 1.00… Transferiste S/ 500.00" → 50000; "Recibiste" → inbound; sin importe → null. Ejemplos Plin/Scotiabank/Dale escritos en el formato genérico (se añadirán las muestras reales del usuario). **Review Focus 2:** mismo pago en dos eventos → un movimiento; mismo `externalRef` → uno; dos cafés iguales con comercio distinto → dos; cuenta por últimos dígitos gana a la fuente; evento ilegible no rompe los demás; procesar dos veces no duplica. Revisión: confirmar quita la marca; borrar recalcula saldo; "por revisar" cuenta en `MonthSummary`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS; `flutter test`.
- [ ] **Step 5: Commit** "Captura: lector, bandeja y movimientos por revisar".

### Task 5: Captura en Android

**Files:**
- Modify: `android/app/src/main/kotlin/com/outflow/outflow/PaymentNotificationListener.kt`, `MainActivity.kt`, `lib/features/wallet/data/payment_listener.dart`, `lib/features/settings/presentation/google_pay_guide_screen.dart` (pasa a **Captura automática**), `lib/features/settings/presentation/settings_screen.dart`
- Create: `android/app/src/main/kotlin/com/outflow/outflow/CaptureStore.kt`
- Test: `android/app/src/test/kotlin/com/outflow/outflow/PaymentParserTest.kt` (se reescribe como `CaptureFilterTest`), `test/google_pay_guide_test.dart`

**Interfaces:**
- Consumes: `CaptureEvent` JSON (`sourceKey` = paquete, `sourceLabel`, `text`, `receivedAt` ISO-8601).
- Produces:
  - `CaptureStore.append(context, event)`: añade línea a `File(context.getDir("flutter", MODE_PRIVATE), "capture_inbox.jsonl")`, la misma ruta que `getApplicationDocumentsDirectory()`; `seenApps(context)`/`enabledApps`, en preferencias privadas.
  - `CaptureFilter.looksLikeMoney(text): Boolean`.
  - El servicio: paquete activado + `looksLikeMoney` → bandeja. Paquete no activado + `looksLikeMoney` → solo se apunta en `seenApps` (sin guardar el texto). Se **elimina** la notificación "¿Registrar este pago?", `PaymentParser` y el canal `outflow_pagos`.
  - Canal `outflow/payments`: añade `seenApps() → List<{package,label}>`, `enabledApps()`, `setEnabled(package, bool)`. Lista conocida activada por defecto: la `SOURCES` actual más Scotiabank y Dale (confirmar el paquete real de Dale con el usuario o en Play Store).
- Pantalla: estado del permiso, lista conocida + apps vistas con interruptor, y cuenta asignada a cada una (`CaptureSourcesRepository`).

- [ ] **Step 1: Tests** — Kotlin: `looksLikeMoney("Pagaste S/ 12.50")` true, "Tienes un mensaje" false. Dart con canal simulado: activar una app vista llama `setEnabled`; elegir cuenta la guarda.
- [ ] **Step 2: Run** `flutter test test/google_pay_guide_test.dart` y `cd android && ./gradlew :app:testDebugUnitTest` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** → PASS; `flutter build apk --debug` compila; en emulador `adb shell cmd notification post` de una app activada → al abrir aparece "por revisar".
- [ ] **Step 5: Commit** "Captura en Android para cualquier entidad".

### Task 6: Captura en iPhone por Atajos y constancias

**Files:**
- Create: `lib/features/capture/domain/capture_link.dart`, `lib/features/settings/presentation/email_capture_guide_screen.dart`
- Modify: `lib/app.dart`, `lib/features/settings/presentation/settings_screen.dart`, `lib/features/receipts/domain/receipt_heuristic.dart`, `lib/features/receipts/domain/receipt.dart`, `lib/features/receipts/presentation/receipt_result_screen.dart`, `lib/features/receipts/presentation/scan_receipt_flow.dart`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/com/outflow/outflow/MainActivity.kt`
- Test: `test/capture_link_test.dart`, `test/receipt_heuristic_test.dart`, `test/receipt_result_test.dart`

**Interfaces:**
- Consumes: `CaptureInbox`, `captureSyncProvider`.
- Produces:
  - `CaptureEvent? parseCaptureLink(Uri uri, {required String expectedKey, required DateTime now})` para `outflow://captura?clave=<k>&fuente=<f>&texto=<t>`; clave distinta o ausente → null; `texto` se corta a 4000 caracteres. Clave por instalación en secure storage (`outflow.capture.key`) que la guía deja copiar.
  - Modo diagnóstico en la guía: **Probar** muestra el último texto recibido y lo que entendió `parseBankText`.
  - `ReceiptData.operationId`, y `receipt_heuristic` reconoce constancias ("Nro. de operación", "Constancia", "Plin", destinatario) → `externalRef` del gasto.
  - Android: filtro `SEND image/*` y canal `outflow/share` → `initialImage()`/`images` (copia el `content://` a caché) que abre `_ReadingScreen`. iPhone: acción **Desde captura** en el selector cámara/galería, sin extensión.
- **Se empieza con el enlace `outflow://`** (abre la app) porque es lo único comprobable sin Mac. App Intent sin abrir la app queda fuera de este plan hasta ver la prueba real.

- [ ] **Step 1: Tests** — **Review Focus 3:** sin clave o con clave errónea → null y no entra en la bandeja; clave correcta → evento; texto de 5000 → 4000. Constancia Plin de ejemplo → importe, destinatario, fecha, `operationId`; capturar la misma operación dos veces → un movimiento.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS; `flutter test`.
- [ ] **Step 5: Commit** "Captura en iPhone por enlace y lectura de constancias".
- [ ] **Step 6: Punto de control con el usuario (no detiene las demás tareas).** Instalar el IPA, seguir la guía con un correo real y usar **Probar**. Si no llega el cuerpo ni basta el asunto, anotarlo: la decisión sobre la captura de iPhone vuelve al usuario, sin bloquear Task 7 y Task 8.

### Task 7: Importar estado de cuenta (Ajustes)

**Files:**
- Create: `lib/features/statements/domain/statement.dart`, `lib/features/statements/domain/parse_statement.dart`, `lib/features/statements/data/pdf_text_reader.dart`, `lib/features/statements/data/statement_ai_reader.dart`, `lib/features/statements/presentation/import_statement_screen.dart`, `ios/Runner/PdfTextPlugin.swift`
- Modify: `pubspec.yaml` (`spreadsheet_decoder`), `android/app/build.gradle.kts` (`com.tom-roush:pdfbox-android`), `android/app/src/main/kotlin/com/outflow/outflow/MainActivity.kt`, `ios/Runner/AppDelegate.swift`, `ios/Runner.xcodeproj/project.pbxproj`, `lib/features/settings/presentation/settings_screen.dart`
- Test: `test/parse_statement_test.dart`, `test/import_statement_test.dart`, `test/statement_ai_reader_test.dart`

**Interfaces:**
- Consumes: `processCaptures` (mismas reglas de duplicado, extraídas a `isDuplicate(...)`), `makeAdjustment`, `GeminiConfig`.
- Produces:
  - `class StatementRow { DateTime date; String description; int amountMinor; bool isCredit; String? operationId; }`, `class ParsedStatement { List<StatementRow> rows; int? closingBalanceMinor; String? currency; }`.
  - `ParsedStatement parseStatementText(String text, {required int year, required String fallbackCurrency})`; `ColumnMapping? detectColumns(List<List<String>> table)` (fecha, descripción, cargo, abono, importe con signo, saldo); `ParsedStatement parseStatementTable(table, ColumnMapping, {fallbackCurrency})`.
  - `enum RowStatus { fresh, alreadyThere }`; `List<(StatementRow, RowStatus)> classifyRows(rows, account, movements)`.
  - `abstract interface class PdfTextReader { Future<String> read(String path, {String? password}); }`, errores `PdfPasswordRequired`, `PdfWrongPassword`, canal `outflow/pdf`. CSV por texto; `.xls` antiguo → mensaje "Guárdalo como .xlsx o CSV".
  - `String maskSensitive(String text)` (secuencias de 8+ dígitos con o sin separadores → asteriscos, sin tocar importes ni fechas); `StatementAiReader` reutiliza el cliente Gemini con ese texto y solo tras el interruptor **Usar IA para leer este archivo**.
- Pantalla **Ajustes → Importar estado de cuenta**: cuenta → archivo → contraseña si la pide → (formato desconocido: elegir columnas) → vista previa con **Nueva** / **Ya registrada**, casillas (nuevas marcadas) → **Importar N movimientos**. Crea `origin: import`, sin `needsReview`, categoría sugerida. Si hay `closingBalanceMinor` distinto del saldo: ofrece **Ajustar a S/ X**. El archivo no se guarda.

- [ ] **Step 1: Tests** — CSV y tabla xlsx con cargo/abono y con importe con signo; PDF de texto con años implícitos y diciembre→enero; filas de totales ignoradas; `detectColumns` en español/inglés. **Review Focus 2:** fila igual a un "por revisar" → `alreadyThere`. Pantalla: PDF con contraseña la pide; importar crea solo las marcadas; ofrecer ajuste. `maskSensitive` oculta `19112345678901` y conserva `1,250.50` y `08/09/2026`; sin interruptor no se llama a Gemini (`MockClient` sin peticiones).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS; `flutter test`; `flutter build apk --debug`. El Swift se comprueba en CI.
- [ ] **Step 5: Commit** "Importar estado de cuenta desde Ajustes".

### Task 8: Gastos compartidos y dinero real

**Files:**
- Modify: `lib/features/friends/domain/split_movements.dart`, `lib/features/friends/presentation/split_editor_screen.dart`, `lib/features/friends/presentation/friend_detail_screen.dart`, `lib/features/friends/presentation/friends_providers.dart`, `lib/features/wallet/domain/wallet_settings.dart`
- Test: `test/split_movements_test.dart`, `test/split_editor_test.dart`, `test/friends_screen_test.dart`

**Interfaces:**
- Consumes: `paidMinor`, `accountId`, `MovementOrigin.settlement`, `adjustmentMinor`, `AccountPicker`.
- Produces:
  - `WalletSettings.splitAccountIds: Map<String,String>` (gasto→cuenta), local.
  - `reconcileSplitMovements`: al **crear** un `split`: `paidMinor` = total si `paidBy == me`, 0 si no; `accountId` de `splitAccountIds`. Al actualizar: conserva `accountId`; recalcula `paidMinor` solo si ya lo tenía. Un `split` antiguo (`paidMinor == null`) sigue moviendo solo tu parte.
  - Editor: si pagas tú, **¿De qué cuenta salió?** (por defecto, la por defecto).
  - `Movement? makeSettlementMovement({required SharedExpense e, required String debtor, required String me, String? accountId, required DateTime now})`: id `settle:<gasto>:<deudor>`; si `debtor != me` entra (+parte); si `debtor == me` sale (−parte); null sin cuenta o si no intervienes. `countsInWallet == false`.
  - Al marcar pagado o **Saldar todo**: hoja opcional **¿En qué cuenta?** con **Ninguna**. Nunca bloquea el saldado.

- [ ] **Step 1: Tests** — pagaste 10000 entre 4: Resumen 2500, cuenta −10000; pagó un amigo: Resumen 2500, cuenta 0; saldar tu deuda de 2500 eligiendo cuenta: −2500 y Resumen igual; **Ninguna** no crea movimiento; `split` antiguo: sigue −parte; borrar el gasto compartido quita su movimiento; el otro participante salda: tu cuenta no cambia.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS; `flutter test`.
- [ ] **Step 5: Commit** "Gastos compartidos: la cuenta refleja lo que salió de verdad".

### Después de las tareas (con el usuario)
- Publicar `firestore.rules` otra vez en la consola: sin eso la sesión única queda inactiva (la app sigue funcionando).
- Aportar un correo y un estado de cuenta de Scotiabank y de Dale con datos tapados, para añadirlos como pruebas y ajustar las reglas.
- Task 6 Step 6: prueba de Atajos en su iPhone.
