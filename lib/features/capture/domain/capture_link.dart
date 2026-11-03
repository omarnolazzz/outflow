import 'process_captures.dart';

/// Tope del texto que se acepta por enlace.
const kCaptureTextLimit = 4000;

/// Tope del nombre de la fuente que escribe el usuario en su atajo.
const kCaptureSourceLimit = 40;

/// `outflow://captura?clave=<k>&fuente=<f>&texto=<t>`: el texto de un correo
/// bancario que envía un atajo de iPhone. Con la clave ausente, vacía o distinta
/// de [expectedKey] devuelve null y no se hace nada: el enlace podría venir de
/// cualquier página o app. La clave no se registra en ningún sitio.
CaptureEvent? parseCaptureLink(Uri uri, {required String expectedKey, required DateTime now}) {
  if (uri.scheme != 'outflow' || uri.host != 'captura') return null;
  if (!_sameKey(uri.queryParameters['clave'] ?? '', expectedKey)) return null;

  final text = _cut(uri.queryParameters['texto'] ?? '', kCaptureTextLimit);
  if (text.trim().isEmpty) return null;

  final typed = _cut((uri.queryParameters['fuente'] ?? '').trim().replaceAll(RegExp(r'\s+'), ' '), kCaptureSourceLimit).trim();
  final label = typed.isEmpty ? 'Correo' : typed;
  return CaptureEvent(
    sourceKey: 'email:${label.toLowerCase()}',
    sourceLabel: label,
    text: text,
    receivedAt: now,
  );
}

/// Compara sin cortar en el primer carácter distinto y sin aceptar nunca una
/// clave vacía.
bool _sameKey(String given, String expected) {
  final a = given.trim();
  if (expected.isEmpty || a.isEmpty || a.length != expected.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return diff == 0;
}

/// Corta a [max] unidades sin partir un par sustituto (emoji).
String _cut(String s, int max) {
  if (s.length <= max) return s;
  final end = (s.codeUnitAt(max - 1) & 0xFC00) == 0xD800 ? max - 1 : max;
  return s.substring(0, end);
}
