# Outflow 2 · Fase 3 (Escanear tickets) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fotografiar o elegir un ticket, leer su texto en el iPhone, completarlo con Gemini (solo texto) y guardar el gasto tras confirmar, sin contar dos veces un pago ya registrado.

**Architecture:** Tres piezas independientes y sustituibles: `TextRecognizer` (Vision de iOS por MethodChannel propio; falso en web/tests), `ReceiptReader` (Gemini por REST con salida JSON; heurística local de respaldo) y la UI de escaneo/resultado. El dominio (`ReceiptData`, heurística, coincidencias) es Dart puro y testeado.

**Tech Stack:** Flutter 3.47.7, Riverpod 3, `image_picker`, `http` (añadir con `flutter pub add`), Swift (Vision) en `ios/Runner`.

**Spec:** `docs/superpowers/specs/2026-10-22-outflow-fases-2-3-4-design.md` (sección Fase 3 y "Decisiones tomadas por Claude")

## Global Constraints
- **La foto nunca sale del iPhone**; a Gemini solo va texto. La foto no se guarda.
- Clave `GEMINI_API_KEY` y modelo `GEMINI_MODEL` (por defecto `gemini-2.5-flash`) por `--dart-define`; secreto en CI. Sin clave → solo heurística.
- Sin red / error / sin clave: siempre se llega a la pantalla de confirmación (heurística).
- Interfaz en español; estilo/animaciones de la fase 1; `AppMotion.reduced`.
- Permisos iOS: `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` en español.
- `flutter analyze` limpio, `flutter test` verde por tarea; commits con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus
1. Ticket con varios importes (subtotal, IGV, total, vuelto) → el total es la línea TOTAL/IMPORTE TOTAL, no el mayor número ni el vuelto. → test Task 1.
2. Respuesta de Gemini mal formada, con importes como texto o sin productos → se usa lo válido y la heurística completa el resto; nunca crash. → test Task 2.
3. Ticket con fecha en formatos `08/09/2026`, `8-9-26`, `2026-09-08` o sin fecha → fecha correcta o hoy. → test Task 1.
4. Pago ya registrado con Apple Pay → "¿Es este pago?" ofrece convertirlo en lugar de duplicar. → test Task 4.
5. El usuario cancela la cámara / niega el permiso → vuelve sin error y con mensaje claro. → test Task 4.

---

### Task 1: Datos del ticket y lector heurístico

**Files:**
- Create: `lib/features/receipts/domain/receipt.dart`, `lib/features/receipts/domain/receipt_heuristic.dart`
- Test: `test/receipt_heuristic_test.dart`

**Interfaces:**
- Produces:
  - `class ReceiptItem { String name; int quantity; int amountMinor; }`
  - `class ReceiptData { String? merchant; DateTime? date; int? totalMinor; String? currency; List<ReceiptItem> items; bool fromAi; }` + `ReceiptData merge(ReceiptData fallback)` (rellena lo que falte).
  - `ReceiptData parseReceiptHeuristic(String text, {required DateTime now, required String fallbackCurrency})` — total: última línea que contenga TOTAL (no SUBTOTAL) / IMPORTE TOTAL / TOTAL A PAGAR; fecha: primer patrón válido no futuro; comercio: primera línea con ≥ 3 letras que no sea RUC/dirección; moneda: S/, PEN, EUR, USD, $ si aparece; productos: líneas "cantidad? nombre importe" entre cabecera y total (best effort).
- [ ] **Step 1: Tests** con el ticket de la referencia (TABERNA LA ALEGRÍA … TOTAL 93,00 EUR, 8 sept 2026) y uno peruano (… OP. GRAVADA, IGV 18%, TOTAL S/ 45.90, VUELTO 4.10): total, fecha, comercio, moneda y ≥ 3 productos; texto vacío → todo null salvo moneda fallback.
- [ ] **Step 2–4.** **Step 5:** Commit "Tickets: lector heurístico".

### Task 2: Lector con Gemini

**Files:**
- Create: `lib/core/config/gemini_config.dart`, `lib/features/receipts/data/gemini_receipt_reader.dart`
- Modify: `.github/workflows/ios-unsigned.yml` (`GEMINI_API_KEY` y `GEMINI_MODEL` como `--dart-define` desde secrets)
- Test: `test/gemini_receipt_reader_test.dart`

**Interfaces:**
- Produces: `abstract interface class ReceiptReader { Future<ReceiptData> read(String text, {required DateTime now, required String fallbackCurrency}); }`; `GeminiReceiptReader(http.Client client, {required String apiKey, required String model})` → POST `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent?key=<apiKey>` con `responseMimeType: application/json` y `responseSchema` (merchant, date YYYY-MM-DD, total number, currency, items[{name, quantity, amount}]); timeout 15 s; cualquier error → heurística. Resultado siempre `merge` con la heurística. `receiptReaderProvider`: Gemini si hay clave, si no un lector solo heurístico.
- [ ] **Step 1: Tests** (`MockClient` de `package:http/testing.dart`): JSON válido → datos y `fromAi: true`, la petición NO contiene base64/imagen y sí el texto; `total` como "45,90" → 4590; respuesta 500 / JSON roto / timeout → resultado de la heurística.
- [ ] **Step 2–4.** **Step 5:** Commit "Tickets: lectura con Gemini".

### Task 3: Leer el texto de la foto en el iPhone

**Files:**
- Create: `ios/Runner/TextRecognitionPlugin.swift` (Vision `VNRecognizeTextRequest`, `.accurate`, idiomas `es-ES`, `en-US`, corrección de idioma; método `recognizeText(path) → String` con líneas en orden de lectura), `lib/features/receipts/data/text_recognizer.dart` (`abstract interface class TextRecognizer { Future<String> recognize(String imagePath); }`, `ChannelTextRecognizer` con `MethodChannel('outflow/ocr')`, `textRecognizerProvider`; en web devuelve un ticket de ejemplo)
- Modify: `ios/Runner/AppDelegate.swift` (registrar el plugin en `didInitializeImplicitFlutterEngine` con `engineBridge.pluginRegistry.registrar(forPlugin:)`), `ios/Runner.xcodeproj/project.pbxproj` (añadir el .swift al target), `ios/Runner/Info.plist` (permisos de cámara y fotos)
- Test: `test/text_recognizer_test.dart`
- [ ] **Step 1: Test** con `TestDefaultBinaryMessengerBinding` simulando el canal: `recognize('/tmp/x.jpg')` envía `{'path': …}` y devuelve el texto; un `PlatformException` → `TextRecognitionFailed`.
- [ ] **Step 2–4.** El Swift solo se compila en CI: tras el push, comprobar que la acción de GitHub pasa. **Step 5:** Commit "Tickets: lectura de texto con Vision".

### Task 4: Escanear y confirmar

**Files:**
- Create: `lib/features/receipts/presentation/scan_receipt_flow.dart` (elegir Cámara/Galería con `image_picker`, pantalla "Leyendo ticket…" con la foto y una línea de escaneo animada, luego resultado), `lib/features/receipts/presentation/receipt_result_screen.dart`, `lib/features/wallet/domain/payment_match.dart`
- Modify: `lib/features/shell/presentation/quick_add_menu.dart` (acción **Escanear ticket**), `lib/app.dart`, `lib/features/wallet/presentation/widgets/movement_sheet.dart` (botón de cámara en la hoja de gasto nuevo)
- Test: `test/payment_match_test.dart`, `test/receipt_result_test.dart`

**Interfaces:**
- Produces: `List<Movement> findMatchingPayments({required List<Movement> movements, required int amountMinor, required String? merchant, required DateTime date, Duration window = const Duration(days: 3)})` — gastos (no de suscripción) con importe ±1 % o mismo comercio normalizado (`normalizeMerchant` de la fase 2), ordenados por cercanía.
- Resultado: comercio, fecha, total (con `AmountKeypad`), lista de productos editable (nombre, importe; borrar con deslizar), categoría sugerida (`suggestCategory`), etiqueta "Leído con IA" si `fromAi`. **Guardar gasto** → si hay coincidencias, hoja "¿Es este pago?" con las candidatas y "No, es otro": elegir una actualiza ese gasto (importe, comercio, nota con los productos) en vez de crear otro; si no, crea `Movement` con `origin: ticket` y los productos en la nota. Botón **Dividir con amigos** visible pero deshabilitado con el texto "Disponible con Amigos" hasta la fase 4.
- [ ] **Step 1: Tests** — `findMatchingPayments`: Apple Pay de S/ 45.90 hace 1 h coincide; S/ 46.20 (≈0.65 %) coincide; S/ 60 otro comercio no; hace 5 días no. Pantalla de resultado: Guardar sin coincidencias crea gasto `ticket` con total y nota de productos; con coincidencia, elegirla actualiza ese gasto y no crea otro; cancelar la cámara (picker devuelve null) cierra sin error.
- [ ] **Step 2–4.** **Step 5:** Commit "Tickets: escanear y confirmar".
