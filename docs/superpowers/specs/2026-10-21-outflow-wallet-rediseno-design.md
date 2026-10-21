# Outflow 2: wallet + suscripciones, rediseño completo

Fecha: 2026-10-21 · Estado: borrador para revisión del usuario

## Intención
Outflow deja de ser solo un recordatorio de suscripciones y pasa a ser una
**wallet personal**: saber cuánto te queda este mes, registrar gastos e
ingresos en segundos, y seguir avisando de cada cobro recurrente (con la
inteligencia de fechas variables que ya tiene). Debe sentirse como una app de
Apple: clara, luminosa, fluida, con animaciones en todas partes y sin tirones.

El usuario la instala en su iPhone con Sideloadly (Apple ID gratuito). Por
ahora la usan él y, en la fase 4, sus amigos. No se publica en App Store.

## Fases
El trabajo se divide en cuatro proyectos; cada uno termina en una versión
instalable. **Este documento diseña la fase 1 en detalle**; las fases 2–4 se
esbozan para que la fase 1 deje sitio a ellas y tendrán su propio diseño.

1. **Rediseño + wallet** (este documento).
2. **Atajo de Apple Pay**: registro automático de pagos con Wallet.
3. **Escáner de tickets con IA gratuita**.
4. **Amigos + dividir gastos** (la cuenta Google se adelanta a la fase 1).

## Decisiones del usuario
- Pantalla principal: **primero la wallet**, debajo **lo próximo que se cobra**.
- Wallet = **un solo número: "Te queda este mes"** = ingresos del mes − gastos
  del mes (no varias cuentas con saldo). El saldo inicial y el sobrante del
  mes anterior entran como ingresos del mes.
- **Configuración inicial guiada** al empezar (moneda, saldo inicial y más).
- Ingresos **variables**: se registran a mano cada vez.
- Estilo **Apple, blanco y claro**, nada de Notion. Las imágenes de
  `referencias/` son solo guía de elegancia (hoja grande de "Add recurring",
  calendario con logos, tarjetas de flujo de caja); **no se copian** sus
  colores oscuros ni su layout literal: se recrea algo propio, igual o mejor.
- La hoja de **agregar suscripción** como la referencia: logo grande, nombre y
  **importe muy grandes**, filas "Frecuencia" y **"Se renueva el …"**, nota.
- **Barra de navegación inferior con efecto cristal** (estilo iOS reciente).
- **Muchas animaciones** en el login y en toda la interfaz, en la línea de los
  videos de referencia ya implementados (intro, entrada escalonada, morph de
  carga); **sin lag**.
- Se **mantiene** todo lo de suscripciones: logos, recordatorios, fechas que
  varían y la pregunta "¿se mantuvo la fecha o varió?" (notificación con
  botones + hoja detallada).
- IA de tickets (fase 3): **gratuita**, uso ocasional.
- La organización de pantallas la decide Claude, pensando en crecer.

## Fase 1 en detalle

### Configuración inicial (pedida por el usuario)
Asistente de pantalla completa, un paso por pantalla, con indicador de
progreso arriba, animación de paso a paso (el contenido sale a la izquierda
y entra desde la derecha) y botón grande "Continuar". Todo se puede cambiar
después en Ajustes; los pasos opcionales tienen "Ahora no".

Orden:
1. **Bienvenida + cuenta**: la intro animada termina en "Bienvenido a
   Outflow" con el botón **"Continuar con Google"** (registro e ingreso son
   el mismo botón, como en otras apps).
2. **Moneda principal**: lista con banderas/símbolos, **S/ (PEN)** preseleccionada.
3. **¿Con cuánto empiezas este mes?**: importe grande con el teclado propio;
   se registra como ingreso "Saldo inicial" del mes actual. Opcional.
4. **¿Lo que te sobre pasa al mes siguiente?**: Sí / No (por defecto Sí).
   Si es Sí, la wallet de cada mes empieza con el sobrante del anterior como
   ingreso "Sobrante de <mes>" (solo si es positivo).
5. **Tus suscripciones**: cuadrícula de logos populares del catálogo; tocas
   las que tienes y para cada una se abre la hoja rápida (importe + "se
   renueva el"). Opcional; se puede saltar.
6. **Avisos**: explica los recordatorios y la pregunta de fechas; pide permiso
   de notificaciones y la hora preferida (por defecto 9:00).
7. **Face ID**: "¿Desbloquear Outflow con Face ID?" Activar / Ahora no.
8. **Listo**: transición a Inicio con la wallet haciendo CountUp desde 0.

**Usuarios que ya tienen datos** (actualizan desde la versión actual): tras
la intro ven "Continuar con Google" y luego un asistente corto con los pasos
2, 3, 4 y 7, una vez. Sus suscripciones se conservan. El PIN desaparece.

### Cuenta y bloqueo (decidido por el usuario)
- **Sin PIN.** La cuenta es **Google** ("Continuar con Google"), vía
  Firebase Authentication. La sesión se mantiene en el iPhone.
- **Pantalla de bloqueo** (al abrir la app y al volver tras > 30 s fuera):
  marca, foto y nombre de la cuenta, y dos opciones:
  - **"Desbloquear con Face ID"**: el escaneo **solo empieza al pulsarlo**
    (nunca automático). Solo aparece si se activó en el paso 7 / Ajustes.
  - **"Continuar con Google"**: vuelve a verificar la cuenta (y permite
    entrar si Face ID falla o no está activado).
- Se conserva la intro animada y el morph de carga (ahora en el botón
  pulsado: el botón se encoge en un indicador de carga, como en el video de
  referencia) y la salida de la pantalla de bloqueo.
- Ajustes: ver la cuenta, activar/desactivar Face ID, **Cerrar sesión**.
- Fase 1: Firebase solo se usa para la cuenta; **los datos siguen solo en el
  iPhone** (Hive cifrado). La sincronización y los amigos llegan en fase 4.
- Requisito de configuración: un proyecto Firebase con Google como
  proveedor, creado por el usuario con su cuenta de Google (Claude da la
  guía paso a paso); el archivo `GoogleService-Info.plist` se añade al
  proyecto iOS. Bundle ID `com.gabrielnolazco.outflow`.
- Sin conexión: si ya hay sesión, Face ID funciona sin internet;
  "Continuar con Google" necesita conexión.

### Navegación (decidido por Claude)
Barra inferior flotante de cristal con **4 pestañas** y un **botón "+"**:

| Pestaña | Contenido |
|---|---|
| **Inicio** | Wallet, próximo cobro, preguntas de fecha pendientes, últimos movimientos |
| **Movimientos** | Todos los gastos e ingresos por día, buscador, filtro por categoría y tipo |
| **Suscripciones** | Calendario del mes con logos en los días de cobro + lista + total mensual |
| **Resumen** | Gasto por categoría (anillo), comparación con el mes anterior, ingresos vs gastos de los últimos 6 meses |

- **Avatar/engranaje arriba a la derecha** en Inicio → **Cuenta y ajustes**
  (cuenta Google y cerrar sesión, moneda principal, sobrante, avisos,
  Face ID, categorías; aquí vivirán el atajo de Apple Pay —fase 2— y los
  amigos —fase 4—).
- **"+"**: abre un menú rápido animado (los botones salen del "+" con
  resorte): **Gasto · Ingreso · Suscripción**; en fase 3 se suma
  **Escanear ticket**.
- Crecer: la fase 4 añade la pestaña **Amigos** (la barra admite 5). Cada
  pestaña es una ruta raíz independiente con su propio `Navigator`, así se
  añaden sin tocar las demás y cada una conserva su scroll.

### Inicio
1. **Wallet** (tarjeta protagonista):
   - Etiqueta "Te queda este mes" y el número enorme (CountUp al aparecer y
     al cambiar).
   - Línea secundaria: "S/ X después de tus cobros pendientes" (resta las
     suscripciones activas que aún se cobrarán en lo que queda del mes).
   - Barra fina de progreso: gastado / ingresado del mes.
   - Dos chips: "Ingresos S/ …" y "Gastos S/ …".
   - **Sin ingresos este mes**: en lugar de un negativo muestra "Gastado este
     mes: S/ …" y un botón discreto "+ Registrar ingreso".
   - Si hay movimientos en otras monedas: "+ US$ 15 en otras monedas" (sin
     conversión; ver Monedas).
2. **Próximo cobro**: tarjeta con logo, nombre, importe y "en 2 días"; desliza
   horizontalmente para los siguientes de los próximos 30 días.
3. **Confirma tu próximo cobro**: las preguntas pendientes de fecha variable
   (igual que hoy, nuevo estilo).
4. **Últimos movimientos**: los 5 más recientes + "Ver todos" → Movimientos.

### Registrar gasto / ingreso
Hoja a pantalla casi completa, mismo lenguaje que la de suscripción:
- Importe **enorme** arriba con teclado numérico propio siempre visible
  (sin teclado del sistema, sin saltos de layout).
- Selector Gasto/Ingreso arriba (segmentado animado).
- Fila horizontal de **categorías con icono** (la última usada preseleccionada).
- Fila "Fecha" (hoy por defecto), "Comercio/Concepto" opcional, "Nota".
- Guardar = ≤ 3 toques en el caso común (importe → categoría → Guardar).
- Al guardar: háptico, la hoja se cierra y el número de la wallet anima su
  cambio.
- Editar y borrar desde el detalle del movimiento (con Deshacer).

### Categorías
Juego por defecto, editable en Ajustes (nombre, icono, color suave):
- Gastos: Comida, Supermercado, Transporte, Hogar, Servicios, Salud, Ocio,
  Compras, Educación, Suscripciones (reservada), Otros.
- Ingresos: Sueldo, Freelance, Ventas, Transferencia recibida, Otros.
Los cobros de suscripciones usan siempre "Suscripciones".

### Suscripciones dentro de la wallet
- Cada cobro de una suscripción **cuenta como gasto del mes el día del cobro**
  sin registrarlo dos veces: el día **previsto** se crea un movimiento
  automático **provisional** (origen "suscripción", con el logo y un id
  único por cobro: suscripción + fecha prevista). No espera a la respuesta.
- Al responder la pregunta de fecha (notificación u hoja), el movimiento se
  **concilia**: pasa a confirmado y, si se corrigió la fecha real del cobro,
  se mueve a esa fecha. Sin respuesta, queda como está (el motor de fechas no
  cambia; esto es una capa encima que lee sus respuestas).
- El usuario puede **editar** el importe de un movimiento automático (solo
  afecta a ese cobro, no a la suscripción) y **borrarlo** (con Deshacer). Un
  borrado se recuerda por su id para no volver a crearlo.
- **"Ya la cancelé" después del cobro (decidido por el usuario: preguntar)**:
  la hoja/app pregunta "¿Te llegaron a cobrar este mes?" →
  **"Sí, me cobraron"** (el gasto se queda; no habrá más cobros) o
  **"No, la cancelé a tiempo"** (el gasto provisional se borra). Desde el
  botón de la notificación (que no puede preguntar), la suscripción se marca
  cancelada y el gasto queda **pendiente de esa pregunta**, que aparece en
  Inicio al abrir la app.
- Suscripciones en pausa/canceladas no generan movimientos nuevos. Las de
  "prueba gratuita" no generan movimientos hasta pasar a activas.
- Primera apertura tras actualizar: se crean los movimientos de los cobros
  previstos **del mes actual** ya pasados (para que la wallet sea correcta
  desde el día 1); nada de meses anteriores.

### Pestaña Suscripciones
- **Calendario mensual** (flechas y gesto para cambiar de mes): cada día con
  cobro muestra el logo (o logos apilados); hoy resaltado; tocar un día filtra
  la lista.
- **Lista** del mes: logo, nombre, frecuencia, importe y estado
  ("Pagado", "Hoy", "en 2 días").
- Total mensual estimado arriba.
- Detalle de suscripción con el mismo contenido que hoy (patrón, últimos
  cobros, aviso de pregunta pendiente), en el nuevo estilo.

### Hoja "Agregar suscripción" (referencia: `agregar suscripcion o pago.jpeg`)
- Barra superior: atrás (círculo) · "Nueva suscripción" · menú (⋯).
- **Logo grande** (≈96 pt) del catálogo actual o imagen propia; tocarlo
  cambia de negocio.
- **Nombre** grande y **importe muy grande** (≈44 pt) editable con el mismo
  teclado numérico.
- Filas tipo tarjeta: **Frecuencia** (Mensual, …), **"Se renueva el"**
  (fecha larga: "miércoles, 21 oct 2026"), **Recordatorio**, **Nota**.
- Botón **Guardar** ancho abajo, en el color de acento.
- La fecha introducida sigue siendo la **próxima fecha de cobro** (como hoy).

### Fechas de cobro variables (se mantiene)
Todo el sistema actual (patrones mismo día / cada N días / día hábil,
historial, sugerencias, notificación con botones al día siguiente, hoja
detallada, uso del historial si no hay respuesta) se conserva **sin cambios
de lógica**; solo cambia su estilo visual.

### Estilo visual (decidido por Claude dentro de "Apple, blanco y claro")
- Fondo **gris muy claro cálido** (≈ #F5F5F7) con **tarjetas blancas** de
  esquinas continuas grandes (≈ 22–24 pt), sombra muy suave y difusa.
- **Un acento** sobrio: verde esmeralda/teal (guiño a las referencias), usado
  en botones primarios, ingresos y selección. Rojo suave solo para vencidos y
  errores. Gastos en tinta, no en rojo.
- Tipografía del sistema (SF Pro): números grandes con cifras tabulares,
  títulos grandes al estilo iOS que se encogen al hacer scroll.
- Iconografía lineal redondeada coherente (se puede seguir con Lucide o
  pasar a Cupertino Icons; decide el builder).
- Modo oscuro: **no** en esta fase (la app fuerza claro); se deja preparado
  con tokens de color.
- Cristal: barra inferior y cabecera al hacer scroll con desenfoque de fondo
  (BackdropFilter) + blanco translúcido + borde fino luminoso.

### Animaciones
- **Login**: se conserva la intro actual (marca que se traza, letras, viaje
  a la pantalla de entrada, morph del botón pulsado a carga, salida de la
  hoja) adaptada a la nueva
  paleta.
- **Entrada** escalonada de tarjetas al llegar a cada pestaña.
- **Barra de cristal**: indicador de la pestaña activa que se desliza con
  resorte entre pestañas; icono que "late" al seleccionarse.
- **"+"**: rota a "×" y despliega las acciones con resorte escalonado.
- **Hojas**: suben con resorte; el importe hace CountUp; las filas entran
  escalonadas.
- **Números** de la wallet y totales: CountUp al cambiar.
- **Listas**: inserción/borrado animados (deslizar + colapsar altura).
- **Calendario**: cambio de mes deslizando; logos aparecen con pop.
- **Pulsación**: todo lo tocable se hunde levemente con resorte + háptico.
- Respeta "Reducir movimiento" (fundidos simples).

### Rendimiento (requisito, no deseo)
- 60/120 fps en un iPhone real en build release: animaciones solo de
  opacidad/transformación; desenfoque solo en la barra y la cabecera (área
  pequeña), nunca en listas enteras.
- Listas largas con construcción perezosa; cálculos del mes memorizados y
  recalculados solo al cambiar datos.
- El inicio de sesión y Face ID nunca bloquean la UI (todo asíncrono, con
  el indicador de carga animado).

### Monedas (decidido por Claude)
- **Moneda principal** elegida en el asistente y cambiable en Ajustes
  (por defecto **PEN, S/**). La wallet suma
  solo movimientos en esa moneda.
- Movimientos y suscripciones pueden estar en otras monedas (como hoy); se
  muestran aparte ("+ US$ 15 en otras monedas"). Sin tipos de cambio en
  esta fase.

### Datos
- Se mantiene Hive cifrado local. Nueva caja de **movimientos**
  (id, tipo gasto/ingreso, importe, categoría, fecha, concepto, nota,
  origen: manual | suscripción | [futuro: apple_pay | ticket | dividido],
  enlace opcional a suscripción). Nueva caja de **categorías**. Ajuste de
  moneda principal.
- El campo **origen** existe desde ya para que las fases 2–4 escriban
  movimientos sin migraciones.
- **Migración**: las suscripciones existentes se conservan tal cual; no se
  generan movimientos retroactivos de meses anteriores (solo desde el mes
  actual en adelante).

### Idioma
Toda la interfaz en español (como hoy).

## Fases 2–4 (esbozo, se diseñarán aparte)
- **Fase 2 — Apple Pay**: en Ajustes, guía paso a paso para crear en la app
  Atajos una automatización "Transacción" (Wallet) que abre Outflow con un
  enlace `outflow://add?amount=…&merchant=…&card=…`; Outflow muestra la hoja de
  gasto prellenada para confirmar con un toque. (Ninguna app puede leer Apple
  Pay directamente.) Google Pay solo existe en Android: se deja el mismo
  enlace preparado, sin probar.
- **Fase 3 — Tickets**: foto o galería → texto leído en el dispositivo
  (Google ML Kit, gratis, sin red) → **Gemini Flash (plan gratuito)** extrae
  comercio, fecha, total y productos → hoja de gasto prellenada. Sin red o si
  falla: total y fecha por heurística. Gemini solo recibe el texto del
  ticket; en el plan gratuito Google puede usarlo para mejorar sus modelos
  (aceptado: uso ocasional).
- **Fase 4 — Amigos**: sobre la cuenta Google de la fase 1, datos
  compartidos en Firestore (gratis a esta escala), lista de amigos por
  invitación, dividir un gasto (partes iguales, por importes o por productos
  del ticket), saldos "te debe / le debes" continuos y liquidar. Con Apple ID
  gratuito **no hay notificaciones push remotas**: los cambios de amigos se
  ven al abrir la app.

## No objetivos (fase 1)
- Conexión con bancos.
- Varias cuentas con saldo propio.
- Presupuestos por categoría y metas de ahorro.
- Conversión de monedas.
- Modo oscuro.
- Cualquier cosa de las fases 2–4.

## Anti-objetivos
- Lag, tirones o animaciones que bloqueen la interacción.
- Que registrar un gasto cueste más de unos pocos toques.
- Perder o alterar datos de suscripciones existentes, o romper la lógica de
  fechas variables y sus notificaciones.
- Copiar literalmente las capturas de referencia.
- Contar un cobro de suscripción dos veces.

## Decisiones tomadas por Claude (revisables)
- Estructura de 4 pestañas + "+" + Ajustes en la cabecera.
- Acento verde esmeralda/teal; fondo gris claro cálido con tarjetas blancas.
- Moneda principal elegida en la configuración inicial (PEN por defecto);
  otras monedas aparte, sin conversión.
- Pasos extra del asistente: sobrante al mes siguiente, suscripciones,
  avisos y Face ID.
- Volver a pedir Google si Face ID no está activado o falla.
- Movimiento automático provisional el día previsto, conciliado al responder.
- Importe editable por cobro; borrado recordado.
- Pruebas gratuitas no cuentan hasta activarse.
- Primera apertura: cuenta los cobros ya pasados del mes actual.
- Sin modo oscuro en fase 1.

## Lo que queda al builder
Paleta exacta y valores de sombra, set de iconos, curvas y duraciones de
cada animación (dentro de los criterios de arriba), estructura de carpetas,
qué widgets actuales se reescriben o adaptan, y diseño del gráfico de
Resumen.
