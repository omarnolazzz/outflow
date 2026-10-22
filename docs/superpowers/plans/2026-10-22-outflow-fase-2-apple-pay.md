# Outflow 2 · Fase 2 (Apple Pay con Atajos) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que un pago con Apple Pay abra Outflow con el gasto ya rellenado (vía la automatización "Transacción" de Atajos) y se guarde con un toque.

**Architecture:** Un enlace `outflow://gasto?importe=…&comercio=…&tarjeta=…` se interpreta con un parser puro → `MovementDraft` → la hoja de gasto existente prellenada. Sugerencia de categoría y aviso de duplicado son funciones puras del dominio de la wallet. El enlace se escucha con `app_links` en `app.dart` y espera al desbloqueo como las notificaciones.

**Tech Stack:** Flutter 3.47.7, Riverpod 3, Hive, `app_links` (añadir con `flutter pub add app_links`).

**Spec:** `docs/superpowers/specs/2026-10-22-outflow-fases-2-3-4-design.md` (sección Fase 2)

## Global Constraints
- Interfaz en español; textos del spec literales: "Registrar pagos con Apple Pay", "Probar".
- Esquema de URL `outflow`, host `gasto`, parámetros `importe`, `comercio`, `tarjeta`.
- Estilo y animaciones del kit de la fase 1; respetar `AppMotion.reduced`.
- Nada de registro silencioso: siempre hoja prellenada con confirmación.
- `flutter analyze` limpio y `flutter test` verde al cerrar cada tarea; commits con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- El workflow de CI no debe romperse por tener ya `CFBundleURLTypes` en `Info.plist` (hoy el paso de Google hace `Add :CFBundleURLTypes array`).

## Review Focus
1. Importe con formatos reales de Atajos ("S/ 12.50", "12,50", "1.234,56", "PEN 12.50", "$12.50", vacío o basura) → importe correcto o hoja vacía, nunca un crash. → test en Task 1.
2. Enlace recibido con la app bloqueada o recién abierta en frío → la hoja aparece tras desbloquear, una sola vez. → test en Task 3.
3. El mismo pago llega dos veces (atajo repetido) → aviso de posible duplicado, no se bloquea guardar. → test en Task 2/3.
4. Comercio con mayúsculas/acentos distintos ("STARBUCKS", "Starbucks Perú") → misma categoría recordada. → test en Task 2.
5. Moneda distinta de la principal en el enlace → el gasto se guarda en esa moneda (cuenta aparte, como en la fase 1). → test en Task 1.

---

### Task 1: Interpretar el enlace de Apple Pay

**Files:**
- Create: `lib/features/wallet/domain/apple_pay_link.dart`
- Test: `test/apple_pay_link_test.dart`

**Interfaces:**
- Produces:
  - `class MovementDraft { int? amountMinor; String? currency; String title; String? categoryId; DateTime? date; MovementOrigin origin; String note; }`
  - `MovementDraft? parseApplePayLink(Uri uri, {required String fallbackCurrency, required DateTime now})` — null si el esquema/host no es `outflow://gasto`. `importe` tolerante (separadores `,`/`.`, símbolos y códigos ISO de `kSupportedCurrencies`/`Fmt.symbol`); `currency` detectada o `fallbackCurrency`; `title` = `comercio` recortado; `note` = "Tarjeta: <tarjeta>" si viene; `origin = applePay`; `date = now`.
- [ ] **Step 1: Tests** — `S/ 12.50`→1250 PEN; `12,50`→1250 fallback; `1.234,56`→123456; `1,234.56`→123456; `PEN 12.50`→PEN; `US$ 9.99`/`USD 9.99`→USD 999; `importe` vacío o "abc" → draft con `amountMinor == null`; otro host → null; `comercio=%20Starbucks%20` → "Starbucks"; `tarjeta=Visa` → nota "Tarjeta: Visa".
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** Verde. **Step 5:** Commit "Apple Pay: interpretar el enlace del atajo".

### Task 2: Categoría sugerida y posible duplicado

**Files:**
- Create: `lib/features/wallet/domain/expense_hints.dart`
- Test: `test/expense_hints_test.dart`

**Interfaces:**
- Produces:
  - `String normalizeMerchant(String s)` — minúsculas, sin acentos, sin espacios extra.
  - `String? suggestCategory({required String merchant, required List<Movement> history, required List<Category> categories})` — 1) categoría del último gasto manual/applePay cuyo `normalizeMerchant(title)` empieza igual (primera palabra) que el comercio; 2) palabras clave (`kCategoryKeywords`: supermercado/plaza vea/tottus/wong/metro/makro → groceries; uber/cabify/didi/taxi/grifo/primax/repsol/pecsa → transport; starbucks/kfc/bembos/pizza/restaurant/cafe/rappi/pedidosya → food; farmacia/inkafarma/mifarma/clinica → health; cine/cineplanet/netflix → leisure; falabella/ripley/oechsle/amazon → shopping); 3) null (la hoja usa la última usada).
  - `Movement? findRecentDuplicate({required List<Movement> movements, required int amountMinor, required String merchant, required DateTime now, Duration window = const Duration(minutes: 2)})` — gasto con mismo importe y mismo comercio normalizado dentro de la ventana.
- [ ] **Step 1: Tests** — "STARBUCKS PERU" recuerda la categoría de un gasto previo "Starbucks"; "Plaza Vea Surco" → groceries por palabra clave; desconocido sin historial → null; duplicado a 1 min → encontrado; a 5 min → null; importe distinto → null.
- [ ] **Step 2–4.** **Step 5:** Commit "Apple Pay: categoría sugerida y aviso de duplicado".

### Task 3: Recibir el enlace y abrir la hoja prellenada

**Files:**
- Modify: `lib/features/wallet/presentation/widgets/movement_sheet.dart` (parámetro `MovementDraft? draft`: importe, concepto, categoría sugerida, nota, origen; banner "Posible duplicado: ya registraste S/ X en <comercio> hace N min" con `findRecentDuplicate`, no bloquea Guardar), `lib/app.dart` (escuchar `AppLinks().uriLinkStream` + enlace inicial; si no está `Ready`, guardar el último draft pendiente y abrirlo al pasar a `Ready`), `ios/Runner/Info.plist` (CFBundleURLTypes con esquema `outflow`), `.github/workflows/ios-unsigned.yml` (añadir el esquema de Google como una entrada más del array existente), `pubspec.yaml`
- Create: `lib/features/wallet/presentation/deep_link_provider.dart` (`incomingLinksProvider` = Stream<Uri>, sustituible en tests; web: stream vacío)
- Test: `test/apple_pay_sheet_test.dart`

**Interfaces:**
- Consumes: `parseApplePayLink`, `suggestCategory`, `findRecentDuplicate`.
- Produces: `showMovementSheet(context, {kind, editing, draft})`; `origin` del draft se guarda en el `Movement`.
- [ ] **Step 1: Tests** — hoja con draft muestra "S/ 12.50" y "Starbucks", Guardar guarda `origin: applePay`, importe 1250, categoría sugerida; con un gasto igual hace 1 min aparece el aviso de duplicado y aun así se puede guardar; `pendingDraft` (lógica extraída en una clase pura `PendingLink` en `deep_link_provider.dart`) entrega el draft una sola vez cuando la sesión pasa a lista.
- [ ] **Step 2–4.** **Step 5:** Commit "Apple Pay: abrir la hoja desde el atajo".

### Task 4: Guía "Registrar pagos con Apple Pay" en Ajustes

**Files:**
- Create: `lib/features/settings/presentation/apple_pay_guide_screen.dart`
- Modify: `lib/features/settings/presentation/settings_screen.dart` (fila nueva en sección Wallet)
- Test: `test/apple_pay_guide_test.dart`

**Contenido:** pasos numerados con iconos (Atajos → Automatización → Nueva → "Transacción" → tarjetas → "Ejecutar inmediatamente" → acción "Abrir URL" → pegar la URL con las variables Importe/Comercio/Tarjeta), bloque con la URL `outflow://gasto?importe=Importe&comercio=Comercio&tarjeta=Tarjeta` y botón **Copiar**, explicación de cómo insertar las variables, botón **Probar** que abre la hoja con un draft de ejemplo (S/ 12.50, "Prueba Apple Pay"). Entradas escalonadas.
- [ ] **Step 1: Tests** — Copiar pone la URL en el portapapeles (mock de `SystemChannels.platform`); Probar abre la hoja con "Prueba Apple Pay".
- [ ] **Step 2–4.** **Step 5:** Commit "Apple Pay: guía en Ajustes".
