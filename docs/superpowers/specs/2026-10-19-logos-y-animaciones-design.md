# Logos reales y animaciones en toda la app

Fecha: 2026-10-19 · Estado: aprobado por el usuario ("hazlo, no más preguntas")

## Intención
Que Outflow se sienta viva en todos lados —desde el PIN hasta cada toque— y
que cada negocio se reconozca a simple vista por su logo real, no por un emoji.

## Objetivos
1. **Logos del catálogo incluidos en la app** (sin internet): un PNG por cada
   comercio del catálogo, obtenido de la web oficial de la marca y normalizado
   a PNG cuadrado (los `.ico` no se pueden mostrar en Flutter/iOS y se
   convierten). Si no hay un logo decente, se muestran las iniciales.
2. **Logo propio en comercios personalizados**: nueva opción "Imagen" junto a
   Emoji / Icono lineal. Se elige desde Fotos o Archivos (PNG, JPG, WebP, ICO…),
   se recorta a cuadrado, se reduce a 256 px y se guarda *dentro de los datos
   de la app* (no como ruta: la ruta del contenedor de iOS cambia al
   reinstalar con Sideloadly).
3. **Animaciones en toda la app**:
   - PIN: entrada del logo, puntos que laten al teclear, temblor + vibración
     si falla, desbloqueo que revela el dashboard.
   - Dashboard: entrada escalonada de secciones y filas, importe que cuenta
     hasta su valor, carrusel con inercia.
   - Navegación: transiciones estilo iOS y logo que "viaja" de la lista al
     detalle (Hero).
   - Toques: respuesta inmediata (ya existe `Pressable`) + vibraciones sutiles
     en acciones importantes.
   - Formularios/ajustes: interruptores, selectores y secciones animadas.

## Restricciones
- Solo APIs de Flutter (sin librerías de animación pesadas); 60/120 fps en iPhone.
- "Reducir movimiento" de iOS → solo fundidos cortos.
- Las suscripciones ya guardadas muestran el logo nuevo sin migración (el logo
  se resuelve por `merchantId` en el catálogo).

## No objetivos
- Descargar logos en tiempo de ejecución.
- Cambiar la identidad visual (paleta, tipografía) de la app.

## Decisiones tomadas por Claude
- Fuente de logos: favicon de alta resolución / apple-touch-icon del dominio
  oficial, procesado a PNG 192 px.
- Selector de archivos: `file_picker` (Fotos y Archivos) + `image` (decodifica
  PNG/JPG/WebP/ICO y redimensiona) en lugar de `image_picker` + `path_provider`.
- Logo personalizado guardado como PNG en base64 (`LogoKind.image`).
