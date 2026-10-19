# Fechas de cobro inteligentes

Fecha: 2026-10-19 · Estado: borrador para aprobación

## Intención
Los cobros reales no siempre caen "el mismo día de cada mes". Ejemplo del
usuario: su tarjeta de crédito pasó del 18 al 19, 20 y 21 en meses sucesivos.
Outflow debe **predecir** el siguiente cobro, **preguntar** tras cada cobro si
la predicción es correcta (con un toque) y **aprender** el patrón de cada
negocio con esas respuestas.

## Comportamiento acordado (decidido por el usuario)
1. Al registrar un negocio se introduce la **próxima fecha de cobro** (como hoy).
   La app calcula los siguientes a partir de ella.
2. **Al día siguiente** de cada cobro previsto, si la suscripción sigue activa,
   llega una **notificación con botones** para responder sin abrir la app:
   confirmar la fecha sugerida, elegir la alternativa o marcar "Ya la cancelé".
3. **Dentro de la app**, la misma pregunta aparece de forma detallada: todas las
   sugerencias explicadas, elegir otra fecha en calendario y corregir la fecha
   real del cobro que acaba de pasar.
4. **Si no responde** por ninguna vía, la app sigue calculando desde la
   **última fecha registrada en el historial** con el patrón aprendido.

## Diseño
### Patrones de cobro
- **Mismo día del mes** (hoy): día D; en meses cortos, el último día.
- **Cada N días**: fecha anterior + N (explica 18 → 19 → 20 → 21 con N = 30/31).
- **Día hábil**: mismo día del mes; si cae en sábado/domingo, pasa al lunes.
- Ciclos semanales/anuales: "mismo día" del ciclo y "cada N días" equivalente.

### Datos (por suscripción)
- `firstChargeDate` pasa a significar **ancla**: el último cobro registrado o,
  si aún no hay ninguno, la próxima fecha introducida al registrar.
- `chargeHistory`: lista de cobros pasados, cada uno con su fecha y si fue
  **confirmado** por el usuario o **asumido** por falta de respuesta.
- `chargePattern`: patrón aprendido o elegido (`null` = mismo día del mes,
  que reproduce el comportamiento actual). Migración: datos existentes quedan
  con historial vacío y patrón `null`, sin cambios visibles.

### Predicción y aprendizaje
- Siguientes cobros = proyección desde el ancla con el patrón.
- Tras cada respuesta: el cobro pasado entra al historial (confirmado), el
  ancla pasa a ser la fecha elegida y se reevalúa el patrón.
- Detección de patrón con ≥ 2 intervalos en el historial: si los intervalos son
  iguales (±1 día) → "cada N días"; si coinciden con el mismo día del mes salvo
  saltos de fin de semana → "día hábil"; si no → "mismo día del mes".
- **Sugerencias** (máx. 3, sin duplicados, la del patrón aprendido primero):
  mismo día del mes, cada N días (N = último intervalo real o 30), siguiente
  día hábil.
- Sin respuesta: cuando pasa el **siguiente** cobro previsto, el anterior pendiente
  entra al historial como **asumido** (no cuenta para aprender el patrón).

### Pregunta pendiente
- Una suscripción tiene pregunta pendiente si su ancla ya pasó y no se ha
  respondido. Como máximo una por suscripción (la más reciente).

### Notificación con botones (iOS)
- Se programa para el día siguiente al cobro previsto, a la hora de los
  recordatorios. Texto: "Netflix · ¿Próximo cobro el 18 dic? Otra opción: 21 dic".
- Botones (textos fijos, limitación de iOS): **Sí, esa fecha** ·
  **Usar la 2ª fecha** · **Ya la cancelé**. Requieren desbloquear el iPhone
  (Face ID/código), no la app.
- La respuesta se guarda sin abrir la app y se aplica a los datos al volver a
  abrirla. Hasta entonces, avisos ya programados pueden basarse en la fecha
  sugerida (limitación aceptada).
- Tocar la notificación (no un botón) abre la pregunta detallada.

### Pregunta detallada en la app
- Dashboard: tarjeta "Confirma tu próximo cobro" por cada pregunta pendiente,
  encima de "Próximos cobros", con la entrada animada de la app.
- Hoja inferior: "¿Cuándo se cobró?" (por defecto la fecha prevista, editable)
  y "¿Cuándo será el próximo?" con sugerencias explicadas
  ("mismo día del mes", "cada 30 días", "siguiente día hábil"), calendario
  para otra fecha y "Ya la cancelé".
- El detalle de la suscripción muestra el historial de cobros y el patrón
  detectado ("Se cobra cada 30 días").

## No objetivos
- Festivos por país (solo fines de semana).
- Leer movimientos bancarios.

## Anti-objetivos
- Preguntar de más: nunca más de una pregunta pendiente por suscripción, ni
  notificaciones repetidas por la misma pregunta.
- Perder la fecha: sin respuesta, la predicción nunca queda vacía.

## Decisiones tomadas por Claude
- Textos fijos en los botones por la limitación de iOS; las fechas van en el texto.
- Respuestas desde la notificación encoladas y aplicadas al abrir la app
  (evita escribir la base de datos cifrada desde un proceso en segundo plano).
- Cobros "asumidos" no entrenan el patrón; solo los confirmados.
- Detección de patrón con tolerancia de ±1 día.
