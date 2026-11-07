# Outflow · Wallet guardada en la nube con la cuenta de Google

Fecha: 2026-11-07 · Estado: borrador para revisión del usuario
Base: wallet con dinero real (`2026-11-03-wallet-real-design.md`), ya instalada.

## Intención
Un usuario desinstaló la app, instaló la versión nueva y **perdió toda su información**, porque la
wallet vivía solo en el teléfono. Para el usuario esto es inaceptable: "no se puede estar perdiendo
la información de los usuarios así por así". La wallet pasa a guardarse en la nube, ligada a la
cuenta de Google: al reinstalar, cambiar de teléfono o usar otro, todo vuelve al entrar con Google.

## Decisión del usuario (2026-11-07)
- **Sí:** la información se guarda en la nube con la cuenta de Google.
- **Una sola wallet por cuenta**, la misma en el iPhone y en el Android. Esto **reemplaza** la
  decisión anterior "cada teléfono lleva su propia wallet" (spec del 2026-11-03).
- La sesión única se mantiene: la cuenta solo está abierta en un dispositivo a la vez.

## Objetivos
1. Nada de lo que el usuario registra se pierde al desinstalar, reinstalar o cambiar de teléfono.
2. La app sigue funcionando sin conexión; los cambios se suben al volver la red.
3. Los usuarios actuales no pierden lo que ya tienen en el teléfono: se sube la primera vez.
4. Un usuario solo puede leer y escribir su propia wallet.

## No objetivos
- Historial de versiones o deshacer en la nube.
- Copias exportables (CSV o PDF) de la wallet.
- Cifrado de extremo a extremo: Firestore cifra en reposo y las reglas limitan el acceso al dueño.
  Con cifrado propio, la clave viviría en el teléfono y se perdería al desinstalar, que es justo el
  problema a resolver. *Decisión de Claude.*
- Recuperar los datos del usuario que ya los perdió: no existe ninguna copia.

## Anti-objetivos
- Que un usuario vea o modifique datos de otro.
- Perder datos al migrar, sobre todo si ambos teléfonos ya tienen datos distintos.
- Que la app deje de abrir o de registrar sin red.
- Duplicar movimientos al unir datos de dos teléfonos.
- Subir a la nube textos bancarios crudos (bandeja de captura, correos, avisos) o claves del
  dispositivo.

## Qué se guarda en la nube y qué no
**En la nube**, en `wallets/{uid}/…`, una colección por tipo, documento por id:
- movimientos, cuentas, suscripciones, comercios propios, categorías;
- ajustes de la wallet: moneda, sobrante, inicio de la wallet, onboarding hecho, cobros borrados,
  avisos descartados, cuentas de gastos compartidos;
- reglas de avisos y la asignación de fuentes de captura a cuentas.

**Solo en el dispositivo:**
- Face ID activado, porque es propio de cada teléfono;
- el id de dispositivo y la clave de captura del enlace;
- las bandejas de captura y respuestas de avisos;
- el diagnóstico de la guía de iPhone;
- las apps de Android vistas o activadas.

Al reinstalar, Face ID y la captura se vuelven a configurar en ese teléfono.

## Cómo funciona
- **Fuente de verdad:** Firestore, con su caché local, como ya hace Amigos. La app lee y escribe a
  través de repositorios de Firestore cuando hay cuenta de Google real. Hive sigue para el modo
  vista previa o web sin Firebase.
- **Sin red:** las lecturas salen de la caché y las escrituras se encolan. No se espera la
  confirmación del servidor para guardar, como ya se hace con Amigos.
- **Conflictos:** gana la última escritura por documento. Con sesión única, dos dispositivos casi
  nunca escriben a la vez.
- **Reglas:** `wallets/{uid}` y todo lo que cuelga de él son de lectura y escritura solo para
  `request.auth.uid == uid`. Se añaden a `firestore.rules` sin tocar lo existente.
- **Borrar toda la información:** también borra `wallets/{uid}` en la nube, con un aviso que lo
  dice claramente. Deja la cuenta como nueva en todos los dispositivos.
- **Cerrar sesión, o perderla por otro dispositivo:** la caché local puede quedarse. Otra cuenta
  nunca ve la wallet de esta, porque cada cuenta lee solo su propio `wallets/{uid}`.

## Migración de quienes ya usan la app
Al entrar con Google en un dispositivo que tiene datos locales en Hive, una sola vez:
1. **Nube vacía:** se sube todo lo local y se marca como migrado.
2. **Nube con datos y local con datos distintos** (el caso de tus dos teléfonos): se pregunta
   **"Este teléfono tiene datos que no están en tu cuenta"**, con dos opciones:
   - **Unir:** se suben solo los elementos cuyo id no exista en la nube.
     - Los ids son únicos, salvo "Mi cuenta" (`default`) y las categorías predeterminadas, que se
       unen sin duplicarse.
     - Los movimientos de "Mi cuenta" de ambos teléfonos quedan en la misma cuenta.
   - **Usar solo los de la nube:** lo local se descarta, previa confirmación.

   *Decisión de Claude:* preguntar en vez de elegir solo, porque unir puede duplicar algo que el
   usuario anotó a mano en ambos teléfonos, y descartar puede perder datos.
3. **Nube con datos y local vacío** (reinstalación): se descarga todo, sin preguntar.

La copia local de Hive no se borra hasta que la subida termina en el servidor. Hasta entonces se
reintenta en cada apertura.

## Precisiones (decisiones de Claude tras la revisión del diseño)
- **Ids:** son únicos entre instalaciones.
  - Lo que crea el usuario usa UUID.
  - Los ids derivados (`sub:<suscripción>:<fecha>`, `split:…`, `settle:…`, `capture:<hash>`)
    dependen de UUIDs o del contenido.
  - Los fijos (`default`, categorías predeterminadas, comercios `cat.*`) representan lo mismo en
    ambos teléfonos.
  - Unir no necesita reasignar ids.
- **Unir es solo una vez y solo añade:** se suben los elementos cuyo id no esté en la nube. Si un
  id está en ambos lados, gana la nube. Tras la migración, la sincronización es en vivo (altas,
  cambios y borrados), y gana la última escritura. Con sesión única, eso basta y no hace falta
  marca de borrado.
- **Ajustes al unir:**
  - Gana la nube en moneda, sobrante, onboarding hecho y reglas de avisos.
  - Se unen los conjuntos: cobros borrados, avisos descartados, cuentas de gastos compartidos y
    fuentes de captura.
  - El inicio de la wallet es el más antiguo de los dos, para no dejar fuera movimientos del otro
    teléfono.
- **"Vacío"** significa que solo hay lo predeterminado: "Mi cuenta" sin saldo inicial ni
  movimientos, categorías predeterminadas, y ninguna suscripción, comercio propio ni movimiento.
  Un teléfono "vacío" descarga sin preguntar.
- **De quién es lo local:** solo se migra lo local si su dueño (`ownerUid`) es la cuenta que entra,
  o si no tiene dueño o es la cuenta de vista previa. Si es de otra cuenta, no se sube ni se
  muestra: queda intacto en el teléfono. Así nunca se mezclan datos de dos cuentas. El modo vista
  previa sin Firebase sigue existiendo y es solo local.
- **Marca de migrado:** se guarda en el dispositivo, por cuenta, y solo cuando el servidor
  confirmó la subida. Si falla, por ejemplo con reglas sin publicar, se reintenta en cada apertura
  sin perder lo local.
- **Borrar toda la información:**
  - Se borra en el cliente, por lotes, colección por colección (plan gratuito, sin funciones en la
    nube).
  - Se escribe una marca de reinicio en `wallets/{uid}` (`resetAt`). Un dispositivo que vea una
    marca más nueva que su última carga descarta su caché.
- **Tamaño:** se escuchan las colecciones completas con caché. Un usuario típico acumula unos
  cientos de movimientos por año, muy dentro de la cuota gratuita. Ventanas o paginación quedan
  para cuando haga falta.
- **Reglas:** el usuario las publica a mano en la consola, como hasta ahora. La app funciona antes
  de publicarlas: muestra el aviso y sigue en local.

## Riesgos
- **Reglas sin publicar:** sin las reglas nuevas, toda escritura en `wallets/{uid}` falla. Se
  detecta y se muestra un aviso claro ("Tu información aún no se está guardando en la nube"), y
  la app sigue funcionando en local hasta que estén publicadas. Las instrucciones para el usuario
  van al final de la entrega.
- **Cuota gratuita de Firestore:** cada usuario genera pocas lecturas y escrituras al día. Se evita
  releer colecciones enteras en cada apertura usando escuchas con caché.
- **Captura y sincronización:** un movimiento capturado se escribe una sola vez. Los ids
  deterministas de captura evitan duplicados aunque dos teléfonos procesen el mismo texto.

## Lo que queda al builder
Estructura exacta de documentos y repositorios, orden de la migración, diseño del diálogo de unir,
pruebas con `fake_cloud_firestore`, y cómo detectar que las reglas no están publicadas.
