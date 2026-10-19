# Fechas de cobro inteligentes — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Predecir el siguiente cobro con patrones (mismo día / cada N días / día hábil), preguntar tras cada cobro (notificación con botones + hoja detallada) y aprender del historial.

**Architecture:** Lógica pura en `subscriptions/domain` (patrón, proyección, sugerencias, confirmación) sobre la entidad `Subscription`, que ya centraliza `nextCharge`/`lastCharge`. El planificador de avisos añade un aviso "confirmar cobro"; las respuestas desde notificación se encolan en un archivo y se aplican al abrir la app.

**Tech Stack:** Flutter 3.47.7, Riverpod 3, Hive CE (JSON), flutter_local_notifications 22.3.2, path_provider.

**Spec:** `docs/superpowers/specs/2026-10-19-fechas-de-cobro-inteligentes-design.md`

## Global Constraints
- Al registrar se introduce la **próxima** fecha de cobro (= ancla `firstChargeDate`).
- Máximo **3** sugerencias; máximo **1** pregunta pendiente por suscripción.
- Botones iOS con texto fijo: `Sí, esa fecha` · `Usar la 2ª fecha` · `Ya la cancelé`; requieren desbloqueo del dispositivo.
- Texto del aviso: `<Nombre> · ¿Próximo cobro el <d MMM>?` + cuerpo `Otra opción: <d MMM>.` (si hay 2ª).
- Sin respuesta → proyección desde la última fecha registrada; los cobros asumidos **no** entrenan el patrón.
- Detección con tolerancia **±1 día**; "cada N días" por defecto N = **30** (mensual).
- Solo fines de semana (sin festivos). Datos existentes: historial vacío, patrón `null` = comportamiento actual.

## Review Focus
1. Día 31 con patrón "mismo día": 31 ene → 28 feb → **31 mar** (sin deriva). → test en Task 1.
2. Día hábil que cruza de mes: 31 may 2026 (domingo) → **1 jun**; el siguiente vuelve a 30 jun (martes). → Task 1.
3. Varios ciclos sin responder: solo la pregunta más reciente queda pendiente; las anteriores pasan a historial como asumidas. → Task 2.
4. Respuesta de notificación obsoleta (ya respondida en la app) se ignora sin tocar datos. → Task 4.
5. Suscripción pausada/cancelada: sin pregunta pendiente ni aviso de confirmación. → Tasks 2 y 3.

---

### Task 1: Patrón de cobro y proyección

**Files:**
- Create: `lib/features/subscriptions/domain/charge_pattern.dart`
- Test: `test/charge_pattern_test.dart`

**Interfaces:**
- Produces:
  - `enum PatternKind { sameDay, everyNDays, businessDay }`
  - `class ChargePattern { const ChargePattern.sameDay(int day); const ChargePattern.everyNDays(int days); const ChargePattern.businessDay(int day); PatternKind kind; int value; DateTime nextAfter(DateTime charge, BillingCycle cycle); String describe(BillingCycle cycle); toJson(); factory fromJson(); == / hashCode }`
  - `nextAfter`: primer cobro estrictamente posterior a `charge`. `sameDay`: avanza `cycle.every` unidades con el día `value` (recorte a fin de mes; semana/día: suma días). `everyNDays`: `charge + value` días. `businessDay`: candidatos mismo día desplazados (sáb +2, dom +1) empezando en el mes de `charge − 3 días`; devuelve el primero > `charge`.
  - `describe`: `Mismo día de cada mes (18)`, `Cada 30 días`, `Día 18 o siguiente día hábil` (anual: `cada año`).

- [ ] **Step 1:** Tests: `sameDay(31)`: 31 ene 2026 → 28 feb → 31 mar; `everyNDays(30)`: 18 ene → 17 feb; `businessDay(31)`: 30 abr 2026 → 1 jun 2026 (31 may es domingo) → 30 jun; `businessDay(18)`: 18 abr 2026 (sábado) es candidato desplazado → 20 abr; JSON ida y vuelta de los tres.
- [ ] **Step 2:** `flutter test test/charge_pattern_test.dart` → FAIL (no existe).
- [ ] **Step 3:** Implementar `charge_pattern.dart`.
- [ ] **Step 4:** Tests → PASS.
- [ ] **Step 5:** Commit `Patrones de cobro`.

### Task 2: Historial, pendiente, sugerencias y confirmación en `Subscription`

**Files:**
- Create: `lib/features/subscriptions/domain/charge_schedule.dart` (sugerencias + inferencia)
- Modify: `lib/features/subscriptions/domain/entities/subscription.dart`, `lib/features/subscriptions/data/subscription_model.dart` (schemaVersion 2, campos opcionales)
- Test: `test/charge_schedule_test.dart`

**Interfaces:**
- Consumes: `ChargePattern` (Task 1).
- Produces:
  - `class ChargeRecord { DateTime date; bool confirmed; toJson/fromJson }`
  - `Subscription`: nuevos campos `List<ChargeRecord> chargeHistory = const []`, `ChargePattern? chargePattern`; `ChargePattern get pattern` (= `chargePattern ?? ChargePattern.sameDay(firstChargeDate.day)`).
  - `Iterable<DateTime> chargesFrom(DateTime from)` (proyección perezosa desde el ancla, ≥ `from`); `nextCharge(now)` y `lastCharge(now)` reescritos sobre ella (último = máx(historial < hoy, proyectados < hoy)).
  - `DateTime? pendingCharge(DateTime now)`: si factura y ancla < hoy → último proyectado < hoy; si no, null.
  - `Subscription confirmCharge({required DateTime pending, required DateTime chargedOn, required DateTime next, ChargePattern? pattern})`: añade asumidos (proyectados entre ancla y `pending`, excluido), añade `chargedOn` confirmado, ancla = `next`, patrón = `pattern ?? inferPattern(...)`.
  - En `charge_schedule.dart`: `class ChargeSuggestion { DateTime date; ChargePattern pattern; String label; }`, `List<ChargeSuggestion> suggestNext(Subscription s, DateTime chargedOn)` (máx 3, sin fechas repetidas, patrón actual primero), `ChargePattern? inferPattern(List<ChargeRecord> history, BillingCycle cycle)` (solo confirmados, ≥ 3 registros = 2 intervalos).
  - Etiquetas: `Mismo día del mes`, `Cada N días`, `Siguiente día hábil`.

- [ ] **Step 1:** Tests: ancla 18 oct, hoy 19 oct → `pendingCharge` = 18 oct; hoy 18 oct → null; pausada → null; hoy 20 dic sin responder → pendiente 18 dic y `nextCharge` = 18 ene; `confirmCharge` desde 18 dic deja historial [18 oct asumido, 18 nov asumido, 18 dic confirmado]; sugerencias para cobro del 18 oct 2026 (domingo) con patrón por defecto: [18 nov, 17 nov, …] sin duplicados y ≤ 3; `inferPattern` con 18 ene, 17 feb, 19 mar (confirmados) → `everyNDays(30)`; con 18 ene, 18 feb, 18 mar → `sameDay(18)`; asumidos ignorados; JSON v1 sin campos nuevos se lee con historial vacío.
- [ ] **Step 2:** Tests → FAIL.
- [ ] **Step 3:** Implementar; `openWindow` sigue funcionando sobre `nextCharge`/`lastCharge`.
- [ ] **Step 4:** `flutter test` (todo, incluidos los 25 existentes) → PASS.
- [ ] **Step 5:** Commit `Historial y confirmación de cobros`.

### Task 3: Aviso "confirmar cobro" en el planificador y el servicio

**Files:**
- Modify: `lib/features/notifications/domain/reminder_planner.dart`, `lib/features/notifications/data/local_notification_service.dart`
- Test: añadir en `test/domain_test.dart`

**Interfaces:**
- Consumes: `chargesFrom`, `suggestNext` (Task 2).
- Produces:
  - `ReminderKind.confirmCharge`; `PlannedReminder` añade `List<DateTime> suggestions` (vacía en los demás tipos).
  - Planner: por cada cobro proyectado `c` en el horizonte, aviso el día `c + 1` a la hora de la regla, con `suggestNext(sub, c)` (máx 2 fechas). Usa `chargesFrom` en lugar de `cycle.nextOnOrAfter`.
  - Servicio: categorías Darwin `confirm2` (acciones `yes`, `alt`, `cancel`) y `confirm1` (`yes`, `cancel`), opción `authenticationRequired`; payload JSON `{"t":"confirm","id","charge","s1","s2"?}` (fechas ISO `yyyy-MM-dd`); otros avisos mantienen payload = id.
  - `Stream<ChargeAnswer> answers` en primer plano; manejador de segundo plano `@pragma('vm:entry-point') void onBackgroundNotification(NotificationResponse r)` que añade una línea JSON a `<documentos>/charge_answers.jsonl`.
  - `class ChargeAnswer { String subscriptionId; DateTime charge; String action; DateTime? date; }` en `lib/features/notifications/domain/charge_answer.dart`.

- [ ] **Step 1:** Test: ancla 18 oct, regla 9:00, hoy 1 oct → el plan contiene `confirmCharge` el 19 oct 9:00 con 1–2 sugerencias; suscripción pausada → ninguno.
- [ ] **Step 2:** FAIL → implementar → PASS.
- [ ] **Step 3:** Commit `Aviso de confirmación de cobro`.

### Task 4: Aplicar respuestas (notificación) al abrir la app

**Files:**
- Create: `lib/features/subscriptions/domain/apply_charge_answer.dart`, `lib/features/notifications/data/charge_answer_inbox.dart`
- Modify: `lib/app.dart` (al iniciar y al volver: vaciar bandeja y escuchar `answers`), `pubspec.yaml` (`path_provider`)
- Test: `test/charge_schedule_test.dart`

**Interfaces:**
- Produces: `Subscription? applyChargeAnswer(Subscription s, ChargeAnswer a, DateTime now)` — null si `a.charge != s.pendingCharge(now)` (obsoleta); `yes`/`alt` → `confirmCharge(chargedOn: a.charge, next: a.date)` con el patrón de la sugerencia; `cancel` → estado cancelada. `ChargeAnswerInbox { Future<List<ChargeAnswer>> drain(); Future<void> add(ChargeAnswer) }` (no-op en web).

- [ ] **Step 1:** Tests: respuesta `yes` aplica; respuesta a un cobro ya confirmado devuelve null; `cancel` cancela.
- [ ] **Step 2:** FAIL → implementar → PASS.
- [ ] **Step 3:** Commit `Respuestas desde notificación`.

### Task 5: UI — tarjeta del dashboard, hoja detallada, historial en el detalle

**Files:**
- Create: `lib/features/subscriptions/presentation/widgets/confirm_charge_sheet.dart`, `.../widgets/pending_charge_card.dart`
- Modify: `dashboard_screen.dart` (sección "Confirma tu próximo cobro" sobre "Próximos cobros", con `Entrance`), `subscription_detail_screen.dart` (callout pendiente con botón, filas "Patrón" e "Historial" con los últimos 6), `subscription_form_screen.dart` (alta: `chargePattern = ChargePattern.sameDay(_date.day)`), `dashboard_summary.dart` (lista `pending`).
- Copy de la hoja: título `Confirma el cobro de <Nombre>`; `¿Cuándo se cobró?` (fecha editable); `¿Cuándo será el próximo?` (sugerencias con etiqueta y fecha, `Otra fecha…` con calendario); botones `Confirmar` y `Ya la cancelé`.

- [ ] **Step 1:** Implementar y `flutter analyze` sin avisos.
- [ ] **Step 2:** Probar en la vista web: suscripción con ancla ayer → tarjeta visible → confirmar → desaparece y el detalle muestra historial/patrón.
- [ ] **Step 3:** `flutter test` → PASS. Commit `Confirmación de cobros en la app`.
