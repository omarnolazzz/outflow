# Outflow · Wallet con dinero real

Fecha: 2026-11-03 · Estado: borrador para revisión del usuario
Base: fases 1–4 ya instaladas (iPhone por Sideloadly, Android por APK).

## Intención
Hoy la wallet es un número que el usuario alimenta a mano y lo siente "dinero
ficticio". Quiere **control y mapeo de sus gastos reales abriendo poco la app**:
que los movimientos se ordenen casi solos y que, cuando entre, el saldo se parezca
al de su banco. Enlazar el banco no es viable hoy en Perú (finanzas abiertas
obligatorias recién hacia 2027–2028), así que se resuelve sin pedir nunca sus
claves bancarias.

## Lo que dijo el usuario
- Quiere: (1) cuentas con saldo real y ajuste manual, (2) captura automática
  ampliada, (3) importar estado de cuenta **en un apartado de Ajustes**.
- Usa Scotiabank (Plin) y Dale, pero **debe servir para cualquier entidad**.
- Usará poco la app; quiere control y mapeo, no estar registrando.
- Cómo le avisan hoy:
  - Transferencias fuertes (p. ej. entre sus propias cuentas): correo a Gmail.
  - Plin pequeño: **nada**, solo la constancia dentro de la app del banco.
  - Dale: constancia en la app y correo con el detalle.
- iPhone es su teléfono principal, pero también usa Android.
- **Cada teléfono lleva su propia wallet**, sin sincronizar, ligada a la cuenta de
  Google.
- **Sesión única:** la cuenta solo está abierta en un dispositivo a la vez, el
  último donde se entró. Entrar en uno nuevo cierra la sesión del anterior.

## Objetivos
1. Cuentas con saldo, cualquier entidad, y ajuste al saldo real.
2. Transferencias entre cuentas propias que no cuentan como gasto ni ingreso.
3. Captura automática sin confirmar cada movimiento, con revisión posterior.
4. Importar estados de cuenta desde Ajustes.
5. Sesión única por cuenta.

## No objetivos
- Enlace con bancos, agregadores (Prometeo…) o pedir claves bancarias.
- Sincronizar la wallet entre teléfonos o guardarla en la nube.
- Conexión directa con la API de Gmail: exige revisión de seguridad anual de Google
  para publicarse, tope de 100 usuarios sin ella y permiso que caduca a los 7 días
  en modo de prueba. Solo se retomaría si la vía de Atajos falla (ver Riesgos).
- Pagos o transferencias reales desde la app.

## Anti-objetivos
- Que una transferencia propia infle gastos o ingresos en el Resumen.
- Contar dos veces un pago (aviso + correo + estado de cuenta + captura).
- Que un aviso mal leído cambie el saldo sin que el usuario pueda verlo y corregirlo.
- Enviar correos o avisos bancarios a la IA: ese texto se interpreta **solo en el
  teléfono**.
- Borrar la wallet local al cerrarse la sesión por entrar en otro dispositivo.

## Cuentas
- Una cuenta tiene nombre, tipo (banco, billetera, efectivo, tarjeta de crédito,
  otra), moneda y saldo inicial con su fecha. Texto libre, sin lista cerrada de
  entidades; se sugieren comunes (BCP, BBVA, Interbank, Scotiabank, Dale, Yape,
  Plin, Efectivo…).
- Saldo de la cuenta = saldo inicial + efecto de sus movimientos.
- **Inicio:** se mantiene "Te queda este mes" (el número principal) y debajo se añade
  "Saldo en cuentas" (total en moneda principal) con la lista de cuentas. *Decisión de
  Claude:* no se reemplaza, porque responden a preguntas distintas (cuánto me queda de
  este mes / cuánto tengo). Las cuentas en otra moneda se muestran aparte, sin convertir,
  igual que hoy.
- Tarjeta de crédito: *decisión de Claude:* su saldo es lo que se debe (negativo) y un
  pago a la tarjeta es una transferencia desde otra cuenta. El gasto cuenta al comprar,
  no al pagar la tarjeta.
- **Ajustar saldo:** en cada cuenta, "Mi saldo real es…". Crea un movimiento de ajuste
  por la diferencia, con su origen visible en el historial.
- **Una cuenta por defecto**, usada cuando un movimiento no indica otra.

### Quienes ya usan la app
Migración sin perder datos: se crea la cuenta "Mi cuenta" en moneda principal con todos
los movimientos existentes, y su saldo inicial queda en 0 para que el saldo resultante
coincida con lo que la app ya mostraba (el "Saldo inicial" del onboarding ya es un
movimiento). El usuario la renombra y ajusta. El onboarding de instalaciones nuevas
pide "tu primera cuenta" en lugar del saldo inicial suelto.

## Tipos de movimiento
Además de gasto e ingreso:
- **Transferencia:** de una cuenta propia a otra (con importe; moneda igual en ambas;
  entre monedas distintas se pide el importe recibido). No suma a gastos, ingresos,
  categorías ni "Te queda". Se ve en Historial con ambas cuentas.
- **Ajuste:** cambia el saldo de una cuenta. No suma a gastos, ingresos, categorías ni
  "Te queda".

Todo movimiento nuevo lleva cuenta. Campos nuevos con valores por defecto para leer los
datos antiguos.

### Gastos compartidos y dinero real
Hoy solo tu parte cuenta (decisión B) y eso **se mantiene** para gastos, categorías y
"Te queda". Pero la cuenta debe reflejar lo que realmente salió del banco:
- **Pagaste tú S/ 100 entre 4:** el Resumen cuenta S/ 25; la cuenta baja S/ 100.
- **Pagó un amigo y le debes S/ 25:** el Resumen cuenta S/ 25; la cuenta no cambia hasta
  que le pagues.
- **Saldar:** al marcar pagada una deuda en la que intervienes se pregunta opcionalmente
  en qué cuenta entró o de cuál salió ("Ninguna" siempre posible). Si eliges una, mueve
  esa cuenta sin contar como ingreso ni gasto. Esto cambia lo acordado en la fase 4
  ("saldar no toca la wallet") solo en lo que toca a **cuentas**; el Resumen sigue igual.
- *Decisión de Claude:* cuando un amigo salda en su teléfono, tu cuenta no se mueve sola
  porque no sabemos dónde recibiste el dinero; lo marca tu captura automática o un ajuste.

### Suscripciones
**Decisión del usuario (2026-11-03, ya aplicada):** los cobros de suscripción se siguen
viendo en Historial, avisos y próximos cobros, pero **no descuentan de la wallet**, porque
los paga a mano y se contarían dos veces (`Movement.countsInWallet`). Tampoco mueven ninguna
cuenta, así que las suscripciones no tienen cuenta de cobro. Cuando pague de verdad, el gasto
entra por la captura automática o a mano como cualquier otro.

## Captura automática
Principio: **se guarda solo y queda "por revisar"**, en vez de pedir confirmación
(*suposición de Claude que el usuario no corrigió*). "Por revisar" cuenta en los saldos, se
distingue visualmente y aparece en una tarjeta de Inicio "N movimientos por revisar",
donde se confirma, corrige o borra.

Un único lector de texto en Dart, usado por todas las fuentes:
- Interpreta importe, moneda, sentido (salió / entró), comercio o destinatario, fecha.
- Reconoce transferencias ("transferencia", "a tu cuenta…") y las propone como
  transferencia entre cuentas propias si reconoce el destino.
- Si no reconoce el importe, no crea nada.
- Reglas genéricas más reglas por entidad para Scotiabank y Dale; se probará con los
  correos reales del usuario (muestras anonimizadas como pruebas).
- Cada fuente se asigna a una cuenta; el usuario lo elige la primera vez y se recuerda.
- Categoría sugerida con la lógica existente (último comercio y palabras clave).

### Duplicados
Antes de guardar: mismo importe y sentido, en la misma cuenta, dentro de una ventana corta
(aprox. 2 días), con comercio compatible o sin comercio → no se crea otro y se completa
el existente con los datos que falten. Si hay duda, se guarda y se marca "¿duplicado?"
en la revisión. Se reutiliza `findMatchingPayments` donde sirva.

### Android
- Se amplía el lector de avisos actual: también ingresos y asignación de cuenta.
- **Cualquier entidad:** Ajustes → "Captura automática" lista las apps del teléfono de las
  que han llegado avisos con un importe, para activarlas, además de la lista conocida.
- El servicio en Kotlin no puede escribir en la base cifrada de Hive: deja lo capturado en
  una bandeja privada de la app (como `ChargeAnswerInbox`) y Dart lo procesa al abrir. Por
  tanto **el saldo se actualiza al abrir la app**, suficiente para el uso del usuario.
  Sustituye la notificación actual "¿Registrar este pago?".

### iPhone
- iOS no deja leer avisos de otras apps. Se usa la **automatización por correo de Atajos**:
  al llegar un correo de la entidad, pasa el asunto y cuerpo a Outflow. Requiere Gmail añadido
  en la app Mail de Apple.
- Preferencia: una App Intent "Registrar movimiento bancario" que guarde en la bandeja sin
  abrir la app; alternativa: `outflow://` que abre la app. El builder elige según la prueba
  en iPhone real (ver Riesgos).
- Guía en Ajustes paso a paso, como la de Apple Pay, por entidad. La de Apple Pay se mantiene.
- SMS del banco: misma automatización con el disparador de Mensajes, para entidades que usen SMS.

### Plin y constancias dentro de la app del banco (no dejan aviso ni correo)
Vía manual rápida: captura de pantalla de la constancia y se lee con el lector de
tickets existente, adaptado a constancias (importe, destinatario, fecha, número de operación).
- Android: compartir la imagen a Outflow.
- iPhone: acción "Desde captura" que abre las fotos; compartir a Outflow solo si funciona con
  la firma de Sideloadly (una extensión de compartir puede no instalarse con Apple ID gratuito).
- El número de operación, si aparece, sirve para detectar duplicados.

## Importar estado de cuenta (Ajustes)
Apartado propio: **Ajustes → Importar estado de cuenta**.
1. Elegir cuenta y archivo: **PDF, Excel (.xlsx) o CSV**. PDF con contraseña: se pide (es
   común en bancos peruanos).
2. La app extrae las filas (fecha, descripción, importe, sentido). Lectura en el teléfono.
   *Decisión de Claude:* la IA (Gemini) es opcional y solo con permiso explícito en esa
   pantalla, enviando el texto del estado de cuenta, nunca el archivo; sin ella, heurística
   local por columnas. Si no se reconoce el formato, se le pide indicar qué columna es cada
   cosa.
3. Vista previa con cada fila marcada como **nueva** o **ya registrada** (mismas reglas de
   duplicados). El usuario desmarca lo que no quiera y confirma.
4. Se importan como confirmados y se propone ajustar la cuenta si el estado de cuenta trae
   saldo final y no coincide.
No se guarda el archivo.

## Sesión única por cuenta
- Cada instalación tiene un id de dispositivo aleatorio. Al entrar con Google se escribe en
  Firestore `sessions/{uid}` = `{deviceId, plataforma, updatedAt}`.
- Mientras la app está abierta y al volver a primer plano, se compara. Si el dispositivo
  registrado es otro, **se cierra la sesión** y se muestra "Tu cuenta se abrió en otro
  dispositivo". Para volver, hay que entrar con Google, lo que a su vez cierra el otro.
- Solo "Continuar con Google" reclama la sesión. Face ID solo desbloquea el dispositivo activo.
- Cerrar sesión **no borra** la wallet local: al volver a entrar con la misma cuenta está
  intacta. Sigue vigente "otra cuenta no abre esta wallet".
- Los movimientos capturados mientras un teléfono está sin sesión esperan en la bandeja y se
  procesan al volver a entrar.
- **Sin red:** un teléfono sin conexión no se entera hasta que reconecta y sigue abierto hasta
  entonces. Es un límite aceptado: lo aplica la app, no impide técnicamente abrir datos locales.
- Si Firestore no responde al entrar, se deja entrar y se reintenta el registro.
- Reglas de Firestore: `sessions/{uid}` solo lectura y escritura del propio usuario.
- Vista previa/web sin Firebase: no aplica.
- **Consecuencia que el usuario debe conocer:** como usa dos teléfonos, cada cambio de
  teléfono exige volver a entrar con Google, y el otro queda con sesión cerrada.

## Borrar toda la información
"Borrar toda la información" también vacía cuentas y bandejas de captura, y conserva la sesión
del dispositivo actual.

## Riesgos y cómo se resuelven
- **El texto del correo en Atajos (el mayor).** No está confirmado que el disparador de correo
  entregue el cuerpo a la acción, ni con cuenta Gmail en Mail. Se prueba **primero**, antes de
  construir el resto de la captura de iPhone, en el iPhone del usuario. Si no entrega el cuerpo:
  usar solo el asunto si basta; si no, se vuelve al usuario para decidir entre la conexión directa
  con Gmail (con sus límites) o la importación mensual como vía principal en iPhone.
- **Formatos reales.** Sin correos ni estados de cuenta reales el lector es una suposición. El
  usuario aporta muestras de Scotiabank y Dale, con sus datos tapados. Otras entidades pasan por
  las reglas genéricas y pueden fallar: el fallo es no crear nada, y queda la importación.
- **Instalación sin cuenta de Apple de pago:** una App Intent o extensión puede no funcionar con
  Sideloadly; por eso hay alternativas sin ellas.
- **Librería de PDF:** debe funcionar en iOS y Android, con contraseña, y sin licencia que obligue a
  pagar. La elige el builder; si no hay opción, primero Excel/CSV y se avisa al usuario.
- **Cambio del modelo de saldos:** mover `MonthSummary` a excluir transferencias y ajustes sin alterar
  los números existentes se cubre con pruebas sobre datos antiguos.

## Precisiones (decisiones de Claude tras la revisión del diseño)
- **A qué cuenta va un movimiento capturado:** cada cuenta admite opcionalmente sus últimos dígitos.
  Se busca en el texto esos dígitos y luego el nombre de la cuenta; si no aparece nada, va a la cuenta
  asignada a esa fuente (una por entidad o app). Una transferencia solo se propone entre cuentas propias
  si se reconoce el destino así; si no, queda como gasto o ingreso "por revisar", y al revisarlo se
  puede convertir en transferencia.
- **"Por revisar" cuenta en todo:** saldos, "Te queda", Resumen y categorías, para que los números no
  difieran entre pantallas. Se distingue a la vista y la tarjeta de Inicio avisa cuántos hay. Corregir o
  borrar uno recalcula todo.
- **Bandeja de captura:** pertenece a la wallet del teléfono, no a una sesión. Se procesa solo al entrar
  la cuenta dueña de la wallet; otra cuenta no puede entrar (regla existente). Se vacía con "Borrar toda
  la información". Guarda solo lo que el lector necesita, en el almacenamiento privado de la app, y se
  borra al procesarse.
- **Si Atajos no entrega el cuerpo del correo:** las etapas 1–3 y 5 no dependen de eso y se entregan
  igual. Importar el estado de cuenta es independiente, no un plan B que dependa de esa decisión. Solo
  la captura automática de iPhone queda en espera de que el usuario decida.
- **Transferencias entre monedas:** un solo registro con importe enviado y recibido. Las capturadas no
  se enlazan solas entre monedas: quedan como dos movimientos por revisar que el usuario puede unir.
- **Datos antiguos:** un movimiento distingue lo que cuenta en el Resumen de lo que mueve la cuenta. Los
  gastos compartidos anteriores mueven solo tu parte, de modo que el saldo mostrado no cambie; los nuevos
  usan el importe real pagado.
- **IA al importar:** solo con permiso explícito en esa pantalla, solo texto, tras descifrar el PDF en el
  teléfono y enmascarar números de cuenta y de documento. Sin permiso, solo lectura local.

## Orden sugerido (cada etapa instalable)
1. Sesión única. 2. Cuentas, transferencias, ajustes y migración. 3. Lector de texto y captura
Android. 4. Prueba de Atajos y captura iPhone; constancias. 5. Importar estado de cuenta.

## Lo que queda al builder
Modelo exacto de datos y migración, diseño de pantallas (estilo Apple actual con animaciones), reglas
del lector, librerías de Excel y PDF, id de dispositivo y mecanismo de escucha de la sesión, ubicación
de la tarjeta "por revisar".
