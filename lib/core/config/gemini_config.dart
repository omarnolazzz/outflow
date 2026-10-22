/// Clave y modelo de Gemini inyectados al compilar (`--dart-define`). Sin
/// clave, los tickets se leen solo en el dispositivo.
abstract final class GeminiConfig {
  static const apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _model = String.fromEnvironment('GEMINI_MODEL');

  /// CI pasa el valor vacío si no existe el secreto: se usa el modelo por defecto.
  static String get model => _model.isEmpty ? 'gemini-2.5-flash' : _model;

  static bool get isConfigured => apiKey.isNotEmpty;
}
