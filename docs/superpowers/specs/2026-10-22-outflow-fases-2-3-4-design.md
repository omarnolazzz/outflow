# Outflow 2 · Fases 2, 3 y 4: Apple Pay, tickets y amigos

Fecha: 2026-10-22 · Estado: borrador para revisión del usuario
Base: fase 1 (`2026-10-21-outflow-wallet-rediseno-design.md`), ya instalada.

## Intención
Que registrar gastos cueste casi nada (pagar con el iPhone o fotografiar el
ticket) y que los gastos compartidos con amigos queden claros sin hojas de
cálculo. Se construyen en orden 2 → 3 → 4; cada fase termina en un IPA
instalable.

## Decisiones del usuario
- Hacer las tres fases.
- **Los amigos instalan Outflow** (iPhone + Sideloadly con su Apple ID).
- **Gasto compartido = solo tu parte cuenta en tu wallet.** Si pagas S/ 100
  entre 4, tu wallet resta S/ 25; los S/ 75 aparecen aparte como "te deben".
  Cuando un amigo te paga, no entra como ingreso: solo se salda la deuda.
  Si le debes a un amigo, tu parte ya contó como gasto; pagarle salda la deuda.
- IA de tickets gratuita (Gemini) que **solo recibe texto**, nunca la foto
  (acordado en la fase 1).

## Fase 2 — Apple Pay con Atajos
- Ninguna app puede leer Apple Pay. Se usa la automatización **"Transacción"**
  de la app Atajos (Wallet): al pagar, ejecuta "Abrir URL"
  `outflow://gasto?importe=<Importe>&comercio=<Comercio>&tarjeta=<Tarjeta>`.
- Outflow registra el esquema `outflow` y abre la **hoja de gasto
  prellenada** (importe, comercio como concepto, fecha de ahora, origen
  `applePay`). Un toque en Guardar.
- Si la app está bloqueada, el enlace espera y se abre al desbloquear (como
  las notificaciones).
- Categoría sugerida: la última usada con ese comercio; si no hay, por
  palabras clave simples (supermercados, transporte, comida…); si no, la
  última categoría usada.
- El importe puede llegar como "S/ 12.50", "12,50", "PEN 12.50": se
  interpreta con tolerancia; si trae otra moneda reconocible se usa esa.
- Aviso de posible duplicado si ya hay un gasto igual (importe y comercio)
  en los últimos 2 minutos.
- **Ajustes → "Registrar pagos con Apple Pay"**: guía paso a paso con
  capturas dibujadas/ilustradas, el texto de la URL para copiar con un toque y
  un botón "Probar" que abre la hoja como lo haría el atajo.

## Fase 3 — Escanear tickets
- Entrada: menú "+" → **Escanear ticket** (y en la hoja de gasto un botón
  de cámara). Cámara o galería.
- **Lectura en el iPhone** con el reconocimiento de texto de iOS (Vision),
  vía código nativo propio (sin dependencias extra). Español e inglés.
- El texto va a **Gemini (plan gratuito)** con salida JSON: comercio, fecha,
  total, moneda y productos (nombre, cantidad, importe). La clave se inyecta
  al compilar (secreto `GEMINI_API_KEY`, igual que Firebase).
- **Sin red, sin clave o si Gemini falla:** heurística local (línea con
  TOTAL/IMPORTE, la fecha más reciente del texto, el comercio = primera línea
  con letras). Nunca bloquea: siempre se llega a la hoja de confirmación.
- Pantalla de resultado: animación de "lectura" sobre la foto, luego
  comercio, fecha, total y lista de productos editables → **Guardar gasto**
  o **Dividir con amigos** (fase 4).
- La foto no se guarda.

## Fase 4 — Amigos y dividir gastos
### Cuentas y amigos
- Requiere Firebase configurado (fase 1) y **Firestore** activado en la
  consola (Claude da la guía y las reglas de seguridad para pegar).
- Al entrar con Google se publica un perfil mínimo: nombre, correo y foto.
- **Añadir amigo por correo**: si esa persona ya usa Outflow, le llega una
  solicitud que acepta o rechaza; aceptada, quedan como amigos. Si no usa
  Outflow, se le dice al usuario que primero debe instalarla.
- Solo los amigos ven tus gastos compartidos con ellos. Nada más de tu
  wallet sale del iPhone.

### Dividir
- Desde: la hoja de gasto (interruptor "Dividir con amigos"), el resultado
  de un ticket, o la pestaña Amigos.
- Quién pagó (tú o un amigo) y entre quiénes se divide.
- Modos: **partes iguales**, **por importes** o **por productos** del
  ticket (tocar quién pidió cada cosa, como la referencia; un producto entre
  varios se reparte a partes iguales).
- Todos los participantes lo ven en su app; quien lo creó puede editarlo o
  borrarlo.

### Wallet y saldos (decisión B del usuario)
- Cada participante tiene en su wallet un gasto con **su parte** (origen
  `split`), creado/actualizado/borrado al sincronizar.
- **Saldos por amigo** (por moneda): "Ana te debe S/ 25", "Le debes a Javi
  S/ 12". Se calculan con los gastos no saldados.
- **Saldar**: "Marcar como pagado" por gasto o "Saldar todo con Ana". No
  crea ingresos ni gastos en la wallet.
- Inicio: tarjeta "Te deben S/ 75 · Debes S/ 12" bajo la wallet.

### Navegación
- Nueva 5.ª pestaña **Amigos** en la barra de cristal: saldos arriba, lista
  de amigos con su saldo, solicitudes pendientes, historial de gastos
  compartidos; "+" para añadir amigo o dividir.

### Sincronización
- Firestore con caché local: funciona sin red y se sincroniza al volver.
- Sin avisos push (Apple ID gratuito): los cambios se ven al abrir la app
  (en tiempo real mientras está abierta).

## No objetivos
- Pagos reales entre amigos (Yape, transferencias).
- Grupos con nombre (viajes, piso): solo amigos individuales por gasto.
- Guardar fotos de tickets.
- Android / Google Pay.

## Anti-objetivos
- Que un amigo vea algo de tu wallet que no sea lo compartido con él.
- Contar dos veces un gasto (Apple Pay + ticket del mismo pago: aviso de
  duplicado).
- Que la falta de red o de IA impida registrar un gasto.

## Riesgos y cómo se resuelven
- **Instalación en el iPhone de un amigo.** Con su Apple ID gratuito,
  Sideloadly puede cambiar el identificador de la app
  (`com.gabrielnolazco.outflow` ya es del usuario). Hay que comprobar que
  "Continuar con Google" sigue funcionando así. La fase 4 empieza con esa
  prueba real (un amigo instala la build de la fase 1 y entra con su Google);
  si falla, se ajusta la configuración de Google/Firebase antes de construir
  nada más.

## Decisiones tomadas por Claude (revisables)
- **Pago con Apple Pay y luego dividido o escaneado:** al dividir o guardar
  un ticket, la app busca gastos parecidos de los últimos 3 días (mismo
  importe ±1 % o mismo comercio) y pregunta "¿Es este pago?". Si el usuario
  dice que sí, ese gasto se convierte (pasa a ser su parte del gasto
  compartido, o se completa con los datos del ticket) en vez de crear otro.
- **Clave de Gemini:** va en la misma build que instalan los amigos (plan
  gratuito, uso ocasional). Si se abusara, se cambia la clave en GitHub y se
  recompila.
- **Saldar:** cualquiera de los dos implicados en una deuda puede marcarla
  como pagada; queda registrado quién y cuándo, y ambos lo ven igual porque
  es un único dato compartido.
- URL de Atajos y hoja prellenada con confirmación (no registro silencioso).
- OCR con Vision de iOS + texto a Gemini (foto nunca sale del iPhone).
- Amigos por correo con solicitud y aceptación.
- Productos compartidos se reparten a partes iguales entre quienes los marcan.
- Saldar no toca la wallet (coherente con la decisión B).

## Lo que queda al builder
Modelo exacto de documentos de Firestore y reglas de seguridad, heurística de
categorías y del lector de tickets, diseño de la guía de Atajos, animaciones.
