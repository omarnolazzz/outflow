# Outflow 2 · Fase 1 (rediseño + wallet) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convertir Outflow en una wallet personal estilo Apple (claro, cristal, muy animada) que conserva todo el sistema de suscripciones y fechas variables, con cuenta Google y configuración inicial guiada.

**Architecture:** Feature-first como hoy (`lib/features/<x>/{domain,data,presentation}`), Riverpod 3 + Hive cifrado (documentos JSON por caja). Se añaden las features `wallet` (movimientos, categorías, resumen del mes, conciliación de cobros de suscripción), `account` (Google + Face ID, sustituye al PIN), `onboarding` y `shell` (barra de cristal con 4 pestañas). Toda la lógica nueva es Dart puro y testeable; la UI se reconstruye sobre un kit de diseño nuevo que sustituye a `notion_widgets`.

**Tech Stack:** Flutter 3.47.7, Dart, flutter_riverpod 3, hive_ce, firebase_core + firebase_auth + google_sign_in (añadir con `flutter pub add`, versiones más recientes compatibles), local_auth, flutter_local_notifications, intl.

**Spec:** `docs/superpowers/specs/2026-10-21-outflow-wallet-rediseno-design.md`

## Global Constraints
- Interfaz 100 % en español; tono y textos del spec literales donde los fija ("Te queda este mes", "Continuar con Google", "Desbloquear con Face ID", "Se renueva el", "¿Te llegaron a cobrar este mes?", "Sí, me cobraron", "No, la cancelé a tiempo").
- Solo tema claro. Fondo ≈ `#F5F5F7`, tarjetas blancas, radio continuo 22–24 pt, un acento verde esmeralda/teal; rojo solo para vencidos/errores; gastos en tinta.
- Animaciones solo de opacidad/transformación; `BackdropFilter` solo en barra inferior y cabecera. Respetar `AppMotion.reduced(context)` en toda animación nueva.
- Nada bloquea el hilo de UI (auth, Face ID y cálculos asíncronos o memorizados).
- **No cambiar la lógica** de `charge_pattern.dart`, `charge_schedule.dart`, `Subscription.chargesFrom/pendingCharge/confirmCharge`, `reminder_planner.dart` ni las notificaciones con botones. Se permiten campos nuevos en `Subscription`.
- Moneda principal por defecto `PEN`; sin conversión entre monedas.
- Hive: cada caja guarda `Map<String,Object?>` JSON por id (patrón de `LocalStore`); campos nuevos siempre opcionales al leer.
- Web preview (`flutter run -d web-server`) debe seguir funcionando: Firebase/Face ID/notificaciones se sustituyen por implementaciones de vista previa cuando `kIsWeb`.
- Bundle ID `com.gabrielnolazco.outflow`; iOS deployment target 15.0 (subir si Firebase lo exige, en el mismo commit).
- `flutter analyze` sin issues y `flutter test` en verde al final de cada tarea. Commits con `git commit -F <archivo>` y la línea `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus
1. **Cambio de mes**: un gasto del 31 a las 23:59 cuenta en ese mes; el 1 a las 00:00 en el siguiente; el sobrante se arrastra solo si es positivo y si el ajuste está activo. → test en Task 3.
2. **Cambio de precio de una suscripción** después de crear el gasto provisional: el provisional toma el nuevo importe salvo que el usuario lo haya editado a mano. → test en Task 4.
3. **Borrar una suscripción** con gastos ya creados: los gastos pasados se quedan; no se crean más. → test en Task 4.
4. **Sin conexión al abrir**: con sesión guardada, el botón de Face ID (con código del iPhone como respaldo del sistema) desbloquea sin red; "Continuar con Google" sin red muestra "Sin conexión" en vez de colgarse. → test en Task 5.
5. **Usuario existente que actualiza**: sus suscripciones siguen intactas, el PIN guardado se ignora y se borra, ve el asistente corto (pasos moneda, saldo inicial, sobrante, Face ID) una sola vez. → test en Task 6.

---

## File Structure

```
lib/core/theme/            app_colors.dart, app_typography.dart, app_theme.dart   (reescritos)
lib/core/widgets/          surface_card.dart, glass.dart, amount_keypad.dart,
                           amount_text.dart, primary_button.dart, sheet_scaffold.dart,
                           list_row.dart, pressable.dart (se conserva), outflow_mark.dart (se conserva)
                           notion_widgets.dart, form_controls.dart, segmented.dart, line_icons.dart → se eliminan/sustituyen en Task 13
lib/features/wallet/
  domain/  movement.dart, category.dart, default_categories.dart, wallet_settings.dart,
           month_summary.dart, charge_movements.dart
  data/    hive_movement_repository.dart, hive_category_repository.dart, wallet_settings_repository.dart
  presentation/ wallet_providers.dart, screens/movements_screen.dart, screens/summary_screen.dart,
           widgets/wallet_card.dart, widgets/movement_sheet.dart, widgets/movement_row.dart
lib/features/account/
  domain/  account.dart, auth_service.dart
  data/    firebase_auth_service.dart, preview_auth_service.dart, local_biometrics.dart
  presentation/ session_controller.dart, welcome_screen.dart, lock_screen.dart (nuevo), splash_intro.dart (movido)
lib/features/onboarding/
  presentation/ onboarding_controller.dart, onboarding_flow.dart, steps/*.dart
lib/features/shell/presentation/ app_shell.dart, glass_tab_bar.dart, quick_add_menu.dart
lib/features/home/presentation/  home_screen.dart
lib/features/subscriptions/presentation/
  screens/subscriptions_screen.dart (calendario+lista, nuevo), subscription_detail_screen.dart (restyle),
  widgets/subscription_editor_sheet.dart (nuevo, sustituye subscription_form_screen.dart),
  widgets/month_calendar.dart, widgets/confirm_charge_sheet.dart (restyle + flujo C),
  widgets/cancel_question_card.dart
lib/features/settings/presentation/ settings_screen.dart (nuevo; absorbe notifications/settings_screen.dart)
lib/features/auth/ → se elimina (PIN) en Task 5
```

---

### Task 1: Kit de diseño Apple claro

**Files:**
- Rewrite: `lib/core/theme/app_colors.dart`, `lib/core/theme/app_typography.dart`, `lib/core/theme/app_theme.dart`
- Create: `lib/core/widgets/surface_card.dart`, `glass.dart`, `amount_keypad.dart`, `amount_text.dart`, `primary_button.dart`, `sheet_scaffold.dart`, `list_row.dart`
- Test: `test/amount_input_test.dart`

**Interfaces:**
- Produces:
  - `AppColors` tokens: `background` (#F5F5F7), `surface` (#FFFFFF), `ink`, `inkSecondary`, `inkTertiary`, `separator`, `accent` (esmeralda), `accentSoft`, `income` (= accent), `danger`, `dangerSoft`, `glassTint`, `glassStroke`, `shadow`. Mantener los nombres antiguos usados por pantallas aún no migradas como alias `@Deprecated` hasta Task 13.
  - `AppType`: `largeTitle` (34/w700), `title1`, `title2`, `headline`, `body`, `callout`, `subhead`, `footnote`, `caption`, `amountHero` (48/w700, tabulares), `amountLarge` (34/w700), `amount` (17/w600). Conservar `display/title/section/bodyStrong/amount` como alias hasta Task 13.
  - `SurfaceCard({required Widget child, EdgeInsets padding, VoidCallback? onTap})` — blanco, radio 22 continuo (`RoundedSuperellipseBorder` si existe en 3.47, si no `ContinuousRectangleBorder`), sombra difusa suave; con `onTap` usa `Pressable`.
  - `Glass({required Widget child, BorderRadius radius, double blur = 24})` — `ClipRRect` + `BackdropFilter` + tinte `glassTint` + borde `glassStroke`.
  - `AmountInput` (ChangeNotifier en `amount_keypad.dart`): `int minor`, `void digit(int d)`, `void decimalPoint()`, `void backspace()`, `void setMinor(int)`, `String display(String currency)`; máximo 9 dígitos enteros, 2 decimales.
  - `AmountKeypad({required AmountInput input})` — teclado 3×4 propio (1–9, `,`, 0, borrar), `Pressable` + háptico por tecla.
  - `AmountText(Money money, {TextStyle? style})` — CountUp al cambiar (reusa `CountUp`).
  - `PrimaryButton({required String label, VoidCallback? onTap, bool loading = false})` — ancho completo, acento; `loading` encoge el botón a un círculo con indicador (morph 320 ms, como el video).
  - `SheetScaffold({required String title, required Widget child, Widget? trailing, Widget? bottom})` — cabecera con botón círculo atrás, título, trailing; `bottom` fijo.
  - `ListRow({required String label, String? value, Widget? leading, VoidCallback? onTap})` — fila tarjeta "Frecuencia ·· Mensual".

- [ ] **Step 1: Test de `AmountInput`**
```dart
test('los dígitos son enteros hasta pulsar la coma; máximo 2 decimales', () {
  final a = AmountInput()..digit(1)..digit(2)..digit(3);
  expect(a.minor, 12300);
  a..decimalPoint()..digit(4)..digit(5)..digit(6);
  expect(a.minor, 12345); // tercer decimal ignorado
  a.backspace();
  expect(a.minor, 12340);
  a..backspace()..backspace()..backspace();
  expect(a.minor, 1200);
  expect(AmountInput().display('PEN'), 'S/ 0');
});
test('máximo 9 dígitos enteros', () {
  final a = AmountInput();
  for (var i = 0; i < 12; i++) {
    a.digit(9);
  }
  expect(a.minor, 99999999900);
});
```
- [ ] **Step 2:** `flutter test test/amount_input_test.dart` → FAIL (no existe).
- [ ] **Step 3:** Implementar tokens, tipografía, tema (Cupertino page transitions ya existentes se conservan; `scaffoldBackgroundColor: background`) y los widgets listados.
- [ ] **Step 4:** Tests en verde + `flutter analyze` limpio (la app aún compila gracias a los alias).
- [ ] **Step 5:** Commit "Kit de diseño claro estilo Apple".

---

### Task 2: Dominio y datos de la wallet

**Files:**
- Create: `lib/features/wallet/domain/movement.dart`, `category.dart`, `default_categories.dart`, `wallet_settings.dart`; `lib/features/wallet/data/hive_movement_repository.dart`, `hive_category_repository.dart`, `wallet_settings_repository.dart`
- Modify: `lib/core/storage/local_store.dart` (cajas `movements`, `categories`)
- Test: `test/wallet_data_test.dart`

**Interfaces:**
- Produces:
  - `enum MovementKind { expense, income }`
  - `enum MovementOrigin { manual, subscription, initialBalance, applePay, ticket, split }` (los tres últimos reservados para fases 2–4).
  - `class Movement { String id; MovementKind kind; Money amount; String categoryId; DateTime date; String title; String note; MovementOrigin origin; String? subscriptionId; bool provisional; bool userEdited; DateTime createdAt; toJson(); fromJson(); copyWith(...) }` — `amount.minor` siempre positivo; el signo lo da `kind`.
  - `class Category { String id; String name; MovementKind kind; String icon (nombre de icono); int color (ARGB suave); bool reserved }` + `const kSubscriptionsCategoryId = 'subscriptions'`.
  - `List<Category> defaultCategories()` con exactamente las del spec (gastos: Comida, Supermercado, Transporte, Hogar, Servicios, Salud, Ocio, Compras, Educación, Suscripciones (reserved), Otros; ingresos: Sueldo, Freelance, Ventas, Transferencia recibida, Otros).
  - `class WalletSettings { String currency = 'PEN'; bool carryOver = true; DateTime? walletStartedAt; bool onboardingDone = false; bool faceIdEnabled = false; Set<String> deletedChargeIds = {}; }` con JSON.
  - `abstract interface class MovementRepository { Stream<List<Movement>> watchAll(); Future<void> save(Movement); Future<void> saveAll(Iterable<Movement>); Future<void> delete(String id); Future<void> deleteAll(Iterable<String> ids); }` + `HiveMovementRepository`.
  - `CategoryRepository` (watchAll/save/delete; siembra `defaultCategories()` si la caja está vacía).
  - `WalletSettingsRepository { Stream<WalletSettings> watch(); WalletSettings read(); Future<void> save(WalletSettings); }` (caja `settings`, id `wallet.settings`).

- [ ] **Step 1: Tests**
```dart
test('Movement sobrevive a JSON (con y sin campos opcionales)', () { ... expect(Movement.fromJson(m.toJson()), equals-by-fields m); });
test('Movement.fromJson acepta JSON mínimo (id, kind, amount, categoryId, date)', ...);
test('defaultCategories: 11 gastos, 5 ingresos, una reservada "subscriptions"', () {
  final c = defaultCategories();
  expect(c.where((x) => x.kind == MovementKind.expense).length, 11);
  expect(c.where((x) => x.kind == MovementKind.income).length, 5);
  expect(c.singleWhere((x) => x.reserved).id, kSubscriptionsCategoryId);
});
test('WalletSettings por defecto: PEN, carryOver true, onboarding pendiente', ...);
```
- [ ] **Step 2:** Ejecutar → FAIL.
- [ ] **Step 3:** Implementar entidades, repos y cajas nuevas en `LocalStore.open`.
- [ ] **Step 4:** Tests verdes, analyze limpio.
- [ ] **Step 5:** Commit "Wallet: movimientos, categorías y ajustes".

---

### Task 3: Resumen del mes (el número de la wallet)

**Files:**
- Create: `lib/features/wallet/domain/month_summary.dart`
- Test: `test/month_summary_test.dart`

**Interfaces:**
- Consumes: `Movement`, `WalletSettings`, `Subscription.chargesFrom`.
- Produces:
  - `class MonthSummary { DateTime month; Money income; Money expense; Money carriedIn; Money remaining; Money afterPending; bool hasIncome; double spentRatio; Map<String, Money> expenseByCategory; List<Money> otherCurrencies; }`
  - `static MonthSummary compute({required List<Movement> movements, required List<Subscription> subscriptions, required WalletSettings settings, required DateTime month, required DateTime now})`
  - Reglas: solo movimientos en `settings.currency` cuentan; el resto se suma por moneda en `otherCurrencies` (gastos − ingresos no; se muestran como neto gastado). `carriedIn` = `remaining` del mes anterior si `carryOver` y > 0 (recursivo hasta el mes de `walletStartedAt`; memorizar por mes). `remaining = carriedIn + income − expense`. `hasIncome = income + carriedIn > 0`. `afterPending = remaining − Σ precios (en moneda principal) de cobros futuros de suscripciones con `status == active` entre mañana y fin de mes que aún no tienen movimiento`. `spentRatio = expense / (income + carriedIn)` acotado 0–1 (0 si no hay ingresos).
  - `Map<DateTime, MonthSummary> lastMonths(int n, ...)` para el Resumen (6 meses).

- [ ] **Step 1: Tests (valores exactos)**
```dart
test('remaining = ingresos − gastos del mes', ...); // ingreso 2000, gastos 300+200 → 1500
test('límite de mes: 31 23:59 cuenta en octubre, 1 nov 00:00 en noviembre', ...);
test('sobrante positivo pasa al mes siguiente si carryOver', ...); // oct 1500 → nov carriedIn 1500
test('sobrante negativo no pasa; carryOver=false no pasa', ...);
test('otras monedas no suman y se listan aparte', ...); // gasto USD 15 → otherCurrencies [US$15], remaining intacto
test('afterPending resta Netflix (29.90, día 25) visto el día 20', ...);
test('sin ingresos: hasIncome false, spentRatio 0', ...);
```
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** Verde. **Step 5:** Commit "Wallet: resumen del mes con sobrante".

---

### Task 4: Cobros de suscripción como gastos (conciliación) + pregunta de cancelación

**Files:**
- Create: `lib/features/wallet/domain/charge_movements.dart`
- Modify: `lib/features/subscriptions/domain/entities/subscription.dart` (campo `DateTime? cancelQuestionCharge` + JSON en `subscription_model.dart`, schemaVersion 3), `lib/features/subscriptions/domain/apply_charge_answer.dart` (cancel desde notificación fija `cancelQuestionCharge = a.charge`), `lib/features/subscriptions/presentation/subscription_providers.dart`
- Test: `test/charge_movements_test.dart`

**Interfaces:**
- Produces:
  - `String chargeMovementId(String subscriptionId, DateTime date)` → `'sub:<id>:<yyyy-MM-dd>'`.
  - `({List<Movement> upsert, List<String> delete}) reconcileChargeMovements({required List<Subscription> subscriptions, required List<Movement> existing, required WalletSettings settings, required DateTime now})`
    - Ocurrencias de una suscripción (solo fechas ≥ inicio del mes de `walletStartedAt` y ≤ hoy): fechas de `chargeHistory` (confirmadas → `provisional=false`; asumidas → `provisional=true`) ∪ cobros de `chargesFrom(firstChargeDate)` ≤ hoy si `status == active` (no `trial`) ∪ `cancelQuestionCharge` si no es null (provisional).
    - Crear las ocurrencias sin movimiento cuyo id no esté en `deletedChargeIds`: gasto, `categoryId: kSubscriptionsCategoryId`, `title: s.name`, importe `s.price`, `origin: subscription`.
    - Actualizar las existentes: `provisional` según ocurrencia; importe = `s.price` salvo `userEdited`.
    - Borrar movimientos `origin == subscription` de suscripciones **existentes** cuya fecha ya no es ocurrencia, que son provisionales y no `userEdited`. Movimientos de suscripciones borradas no se tocan.
  - En `SubscriptionActions`: `Future<void> resolveCancelQuestion(Subscription s, {required bool wasCharged})` — `wasCharged` añade `ChargeRecord(date: cancelQuestionCharge, confirmed: true)` al historial; ambos limpian el campo. `Future<void> cancelAfterCharge(Subscription s, DateTime pending, {required bool wasCharged})` para el flujo dentro de la app (marca cancelada + mismo efecto, sin pregunta pendiente).
  - Provider `chargeMovementSyncProvider` (en `wallet_providers.dart`, Task 7/8 lo observan desde la app): escucha suscripciones + movimientos + ajustes y aplica `reconcile` con `saveAll`/`deleteAll` (debounce por microtarea, sin bucles: no reescribe si no hay diferencias).

- [ ] **Step 1: Tests**
```dart
test('cobro previsto ayer crea gasto provisional con id estable', ...);
test('confirmar con fecha real distinta mueve el gasto (borra provisional, crea confirmado)', ...);
test('prueba gratuita no genera gastos', ...);
test('pausada: conserva los del historial, no crea nuevos', ...);
test('id en deletedChargeIds no se recrea', ...);
test('cambio de precio actualiza provisional salvo userEdited', ...);              // Review Focus 2
test('suscripción borrada: sus gastos pasados se quedan', ...);                      // Review Focus 3
test('nada antes del mes de walletStartedAt', ...);
test('cancel desde notificación: cancelQuestionCharge mantiene el gasto hasta responder; "no" lo borra; "sí" lo confirma', ...);
test('reconcile sobre su propia salida no produce cambios (idempotente)', ...);
```
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** Verde (incluidos los 64 tests previos: la lógica de fechas no cambia). **Step 5:** Commit "Cobros de suscripción como gastos de la wallet".

---

### Task 5: Cuenta Google + bloqueo con Face ID (sustituye al PIN)

**Pre-requisito del usuario:** proyecto Firebase con proveedor Google y app iOS `com.gabrielnolazco.outflow` creada; valores (`API_KEY`, `GOOGLE_APP_ID`, `GCM_SENDER_ID`, `PROJECT_ID`, `CLIENT_ID`, `REVERSED_CLIENT_ID`) entregados. Claude da la guía antes de empezar esta tarea. Si aún no están, la tarea se implementa con `lib/core/config/firebase_config.dart` leyendo `--dart-define` y la app usa `PreviewAuthService` cuando faltan.

**Files:**
- Create: `lib/core/config/firebase_config.dart`, `lib/features/account/**` (ver File Structure)
- Move: `lib/features/auth/presentation/splash_intro.dart` → `lib/features/account/presentation/splash_intro.dart`
- Delete: `lib/features/auth/**` (PIN), `test` que dependan del PIN si los hay
- Modify: `lib/main.dart` (Firebase.initializeApp con opciones de `firebase_config.dart`, salvo web), `lib/app.dart` (capa de bloqueo usa `sessionControllerProvider`), `ios/Runner/Info.plist` (`CFBundleURLTypes` con `REVERSED_CLIENT_ID`, `GIDClientID`), `pubspec.yaml`, `.github/workflows/ios-unsigned.yml` (pasar `--dart-define` desde secrets si se usan)
- Test: `test/session_controller_test.dart`

**Interfaces:**
- Produces:
  - `class Account { String uid; String email; String displayName; String? photoUrl; }`
  - `abstract interface class AuthService { Account? get current; Future<Account> signInWithGoogle(); Future<void> signOut(); }` — `signInWithGoogle` lanza `AuthOffline` / `AuthCancelled` / `AuthFailed(message)`.
  - `abstract interface class Biometrics { Future<bool> isAvailable(); Future<String> label(); Future<bool> authenticate(String reason); }` (local_auth con `biometricOnly: false` → el sistema ofrece el código del iPhone como respaldo).
  - `sealed class SessionState`: `SessionLoading`, `SignedOut`, `Locked(Account, {bool faceId, String faceIdLabel})`, `NeedsOnboarding(Account, {bool short})`, `Ready(Account)`.
  - `SessionController extends Notifier<SessionState>`: `Future<void> continueWithGoogle()`, `Future<bool> unlockWithFaceId()` (solo al pulsar; **nunca** automático), `void lock()` (desde `app.dart` tras >30 s fuera, solo si `Ready`), `Future<void> signOut()`, `Future<void> finishOnboarding()`. Al arrancar: sin cuenta → `SignedOut`; con cuenta y onboarding pendiente → `NeedsOnboarding`; con cuenta → `Locked`. Borra la clave del PIN antiguo en secure storage al arrancar.
  - UI: `WelcomeScreen` (intro de `splash_intro.dart` adaptada → "Bienvenido a Outflow" + `PrimaryButton('Continuar con Google', loading: …)`), `LockScreen` nueva (marca, foto+nombre, `PrimaryButton('Desbloquear con Face ID')` si `faceId`, botón secundario "Continuar con Google", mensaje "Sin conexión" en `AuthOffline`). Intro solo en el primer arranque del proceso (como hoy). Salida de la capa: hoja que baja (como hoy).

- [ ] **Step 1: Tests con fakes de `AuthService`/`Biometrics`/`WalletSettingsRepository`**
```dart
test('sin cuenta → SignedOut; continueWithGoogle → NeedsOnboarding(short:false) en instalación nueva', ...);
test('con cuenta y onboarding hecho → Locked; nunca llama a authenticate sin acción del usuario', ...);
test('unlockWithFaceId true → Ready; false → sigue Locked', ...);
test('continueWithGoogle sin red → Locked/SignedOut se mantiene y expone error offline', ...);   // Review Focus 4
test('usuario con suscripciones y onboarding pendiente → NeedsOnboarding(short:true)', ...);     // Review Focus 5
test('arranque borra la clave del PIN antiguo', ...);
```
- [ ] **Step 2:** FAIL. **Step 3:** Implementar (Firebase solo fuera de web; `PreviewAuthService` en web y cuando falte config). **Step 4:** Verde; `flutter build ios --no-codesign` no se puede en Windows → verificar en CI tras el push. **Step 5:** Commit "Cuenta Google y desbloqueo con Face ID".

---

### Task 6: Configuración inicial guiada

**Files:**
- Create: `lib/features/onboarding/presentation/onboarding_controller.dart`, `onboarding_flow.dart`, `steps/{currency_step,starting_balance_step,carry_over_step,subscriptions_step,notifications_step,face_id_step,done_step}.dart`
- Test: `test/onboarding_controller_test.dart`

**Interfaces:**
- Consumes: `SessionController.finishOnboarding`, `WalletSettingsRepository`, `MovementRepository`, `Biometrics`, `notificationServiceProvider`, catálogo de comercios, `SubscriptionEditorSheet` (Task 10; hasta entonces el paso de suscripciones abre la hoja actual).
- Produces:
  - `enum OnboardingStep { currency, startingBalance, carryOver, subscriptions, notifications, faceId, done }`
  - `OnboardingController(short: bool)` con `List<OnboardingStep> steps` (completo: todos; corto: currency, startingBalance, carryOver, faceId, done), `int index`, `next()`, `back()`, `setCurrency`, `setStartingBalance(int minor)`, `setCarryOver(bool)`, `setFaceId(bool)`, `Future<void> complete(DateTime now)` → guarda `WalletSettings(currency, carryOver, faceIdEnabled, walletStartedAt: now, onboardingDone: true)` y, si saldo > 0, un `Movement` ingreso `origin: initialBalance`, título "Saldo inicial", categoría ingreso "Otros", fecha `now`.
  - UI: barra de progreso arriba, transición entre pasos (sale a la izquierda/entra por la derecha con fundido, 380 ms), `PrimaryButton('Continuar')`, "Ahora no" en pasos opcionales, paso final hace CountUp desde 0 al entrar a Inicio.

- [ ] **Step 1: Tests**
```dart
test('flujo completo tiene 7 pasos; corto tiene 5 y empieza en moneda', ...);
test('complete guarda ajustes y crea "Saldo inicial" solo si > 0', ...);
test('moneda por defecto PEN; carryOver por defecto true', ...);
```
- [ ] **Step 2–4:** FAIL → implementar → verde. **Step 5:** Commit "Configuración inicial guiada".

---

### Task 7: Shell con barra de cristal y botón "+"

**Files:**
- Create: `lib/features/shell/presentation/app_shell.dart`, `glass_tab_bar.dart`, `quick_add_menu.dart`
- Modify: `lib/app.dart` (`home: AppShell()`; observa `chargeMovementSyncProvider` y `reminderSyncProvider`; enruta notificaciones a la pestaña Suscripciones)
- Test: `test/app_shell_test.dart`

**Interfaces:**
- Produces:
  - `enum AppTab { home, movements, subscriptions, summary }` (Amigos se añadirá en fase 4).
  - `AppShell`: `IndexedStack` de 4 `Navigator` (uno por pestaña, conservan scroll); volver a tocar la pestaña activa hace pop al inicio y scroll arriba.
  - `GlassTabBar({required AppTab current, required ValueChanged<AppTab> onSelect})`: cápsula flotante con `Glass`, indicador que se desliza con resorte (`AppMotion.standard`) e icono que hace `SelectionPop`.
  - `QuickAddMenu`: botón "+" circular de cristal a la derecha de la barra; al pulsar rota 45° a "×", oscurece el fondo y despliega Gasto · Ingreso · Suscripción con resorte escalonado (40 ms). Callbacks abren `MovementSheet(kind)` (Task 9) y `SubscriptionEditorSheet` (Task 10) — hasta que existan, stubs que abren la pantalla actual.
- [ ] **Step 1: Widget tests** — cambiar de pestaña muestra su pantalla y conserva el estado de las otras; pulsar "+" muestra las 3 acciones y un segundo toque las cierra.
- [ ] **Step 2–4.** **Step 5:** Commit "Barra de cristal y acciones rápidas".

---

### Task 8: Inicio

**Files:**
- Create: `lib/features/home/presentation/home_screen.dart`, `lib/features/wallet/presentation/widgets/wallet_card.dart`, `lib/features/subscriptions/presentation/widgets/cancel_question_card.dart`, `lib/features/wallet/presentation/wallet_providers.dart` (providers de movimientos, categorías, ajustes, `monthSummaryProvider(month)`, `chargeMovementSyncProvider`)
- Modify: `upcoming_carousel.dart`, `pending_charge_card.dart` (restyle)
- Delete al final de la tarea: `dashboard_screen.dart`
- Test: `test/home_screen_test.dart`

**Interfaces / contenido (orden fijo del spec):**
- Cabecera grande "Inicio" que se encoge con scroll (cabecera de cristal al desplazarse) + avatar a la derecha → `SettingsScreen` (Task 12).
- `WalletCard(summary)`: "Te queda este mes" + `AmountText` héroe; "S/ X después de tus cobros pendientes"; barra fina `spentRatio`; chips Ingresos/Gastos; sin ingresos → "Gastado este mes: S/ …" + "+ Registrar ingreso"; "+ US$ 15 en otras monedas" si aplica.
- "Próximo cobro": carrusel de los cobros de los próximos 30 días.
- "Confirma tu próximo cobro": tarjetas pendientes (existentes) + `CancelQuestionCard` ("¿Te llegaron a cobrar este mes?" Sí, me cobraron / No, la cancelé a tiempo).
- "Últimos movimientos": 5 `MovementRow` + "Ver todos" → pestaña Movimientos.
- Entradas escalonadas al abrir (Entrance) y CountUp.
- [ ] **Step 1: Widget tests** con providers sobrescritos: muestra "Te queda este mes" y el importe; sin ingresos muestra "Gastado este mes"; con `cancelQuestionCharge` muestra la pregunta y "No, la cancelé a tiempo" llama a `resolveCancelQuestion(wasCharged: false)`.
- [ ] **Step 2–4.** **Step 5:** Commit "Inicio con la wallet".

---

### Task 9: Registrar gastos/ingresos y pestaña Movimientos

**Files:**
- Create: `lib/features/wallet/presentation/widgets/movement_sheet.dart`, `movement_row.dart`, `lib/features/wallet/presentation/screens/movements_screen.dart`, acciones `WalletActions` en `wallet_providers.dart`
- Test: `test/movement_sheet_test.dart`

**Interfaces:**
- `WalletActions { Future<void> save(Movement); Future<Movement?> delete(String id) /* devuelve el borrado para Deshacer; si origin==subscription añade su id a deletedChargeIds */; Future<void> restore(Movement) /* quita el id de deletedChargeIds */ }`
- `showMovementSheet(context, {MovementKind kind, Movement? editing})`: `SheetScaffold`; segmentado Gasto/Ingreso; importe `amountHero` + `AmountKeypad`; fila horizontal de categorías (última usada preseleccionada; la reservada no aparece en manuales); filas Fecha (hoy), Concepto, Nota; `PrimaryButton('Guardar')`. Editar un movimiento de suscripción marca `userEdited = true` y solo permite cambiar importe, fecha y nota.
- `MovementsScreen`: lista perezosa agrupada por día (cabecera "Hoy", "Ayer", "lunes 18 oct"), buscador en la cabecera de cristal, filtros tipo (Todos/Gastos/Ingresos) y categoría; deslizar para borrar con Deshacer; inserción/borrado animados.
- [ ] **Step 1: Tests** — caso común en 3 toques (importe → categoría → Guardar) guarda un gasto con la fecha de hoy; borrar un gasto de suscripción y deshacer lo restaura y lo saca de `deletedChargeIds`.
- [ ] **Step 2–4.** **Step 5:** Commit "Registrar gastos e ingresos".

---

### Task 10: Pestaña Suscripciones, hoja nueva y flujo "Ya la cancelé"

**Files:**
- Create: `lib/features/subscriptions/presentation/screens/subscriptions_screen.dart`, `widgets/month_calendar.dart`, `widgets/subscription_editor_sheet.dart`
- Modify: `subscription_detail_screen.dart`, `confirm_charge_sheet.dart`, `catalog_screen.dart`, `create_merchant_screen.dart`, `subscription_tile.dart` (restyle al kit nuevo)
- Delete: `subscription_form_screen.dart` (su lógica de `keepAnchor`/historial/patrón se traslada tal cual a la hoja nueva)
- Test: `test/subscription_editor_test.dart`, `test/month_calendar_test.dart`

**Interfaces / contenido:**
- `SubscriptionsScreen`: total mensual estimado arriba; `MonthCalendar(month, chargesByDay, onDay)` (cuadrícula L–D, flechas y swipe para cambiar de mes con deslizamiento, logos con pop, hoy resaltado, tocar día filtra); lista del mes con estado "Pagado" / "Hoy" / "en N días".
- `Map<DateTime, List<Subscription>> chargesInMonth(List<Subscription>, DateTime month)` (pura, en `month_calendar.dart` o dominio) usando historial + `chargesFrom`.
- `showSubscriptionEditor(context, {Subscription? editing, Merchant? merchant})`: barra con atrás circular · "Nueva suscripción"/"Editar" · ⋯ (borrar); logo 96 pt (tocar → catálogo); nombre `title1`; importe `amountHero` editable con `AmountKeypad`; filas `ListRow` Frecuencia, **Se renueva el** (fecha larga "miércoles, 21 oct 2026"), Recordatorio, Nota; `PrimaryButton('Guardar')`. Misma semántica de fecha que hoy (próxima fecha de cobro) y misma preservación de `chargeHistory`/`chargePattern`.
- `confirm_charge_sheet`: "Ya la cancelé" abre una segunda pregunta en la misma hoja: "¿Te llegaron a cobrar este mes?" → `cancelAfterCharge(wasCharged: true|false)`, con Deshacer.
- [ ] **Step 1: Tests** — `chargesInMonth` pone Netflix (día 18, mensual) el 18 y una suscripción "cada 30 días" en sus días correctos; guardar desde el editor una suscripción nueva fija `firstChargeDate` = fecha elegida; editar sin tocar la fecha conserva historial y patrón.
- [ ] **Step 2–4.** **Step 5:** Commit "Suscripciones: calendario y hoja nueva".

---

### Task 11: Pestaña Resumen

**Files:**
- Create: `lib/features/wallet/presentation/screens/summary_screen.dart`, `widgets/category_ring.dart`, `widgets/month_bars.dart`
- Test: `test/summary_screen_test.dart`

**Contenido:** selector de mes; anillo de gasto por categoría (`CustomPainter`, segmentos que se dibujan con barrido al entrar, colores de cada categoría) + leyenda con importes y %; "vs mes anterior" (↑/↓ %); barras ingresos vs gastos de los últimos 6 meses (crecen desde 0 escalonadas). Sin datos: estado vacío amable. Usa `MonthSummary.lastMonths`.
- [ ] **Step 1: Test** — con gastos Comida 300 y Transporte 100 la leyenda muestra 75 % y 25 %; sin movimientos muestra el estado vacío.
- [ ] **Step 2–4.** **Step 5:** Commit "Resumen del mes".

---

### Task 12: Ajustes

**Files:**
- Create: `lib/features/settings/presentation/settings_screen.dart`, `category_editor_screen.dart`
- Modify/Delete: `lib/features/notifications/presentation/screens/settings_screen.dart` (absorbido), `notification_rule_editor.dart` (restyle)
- Test: `test/settings_screen_test.dart`

**Contenido:** tarjeta de cuenta (foto, nombre, correo, "Cerrar sesión" con confirmación); Moneda principal; "Lo que te sobre pasa al mes siguiente" (switch); Face ID (switch, pide autenticación para activar); Avisos (regla global existente); Categorías (lista, editar nombre/icono/color, añadir; la reservada no se borra); versión.
- [ ] **Step 1: Test** — desactivar el sobrante actualiza `WalletSettings.carryOver`; "Cerrar sesión" confirma y llama a `signOut`.
- [ ] **Step 2–4.** **Step 5:** Commit "Ajustes".

---

### Task 13: Limpieza, pulido de movimiento y verificación

**Files:**
- Delete: `lib/core/widgets/notion_widgets.dart`, `form_controls.dart`, `segmented.dart`, `line_icons.dart` (o lo que ya no se use) y los alias `@Deprecated` de Task 1
- Modify: lo que aún los use

- [ ] **Step 1:** `grep -rn "notion_widgets\|@Deprecated" lib` vacío; `flutter analyze` limpio; `flutter test` verde.
- [ ] **Step 2:** Recorrido completo en la vista previa web (Playwright, 390×844): intro → Bienvenida → asistente completo → Inicio (CountUp) → registrar gasto en 3 toques → Movimientos → Suscripciones (calendario, editor nuevo) → Resumen → Ajustes. Capturas de cada pantalla revisadas contra el spec (claro, cristal, acento único, sin restos Notion).
- [ ] **Step 3:** Revisión de "Reducir movimiento" (emulación `prefers-reduced-motion`) y de que la barra de cristal es el único `BackdropFilter` en scroll.
- [ ] **Step 4:** Push → CI "iOS IPA sin firmar" en verde.
- [ ] **Step 5:** Commit "Limpieza del estilo anterior".
