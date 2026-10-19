import 'package:meta/meta.dart';

/// Botones de la notificación "¿tu próximo cobro es el …?".
enum ChargeAnswerAction {
  /// "Sí, esa fecha": la primera sugerencia.
  yes,

  /// "Usar la 2ª fecha".
  alt,

  /// "Ya la cancelé".
  cancel,
}

/// Respuesta a la pregunta de un cobro, tal como llegó desde la notificación.
@immutable
class ChargeAnswer {
  const ChargeAnswer({
    required this.subscriptionId,
    required this.charge,
    required this.action,
    this.next,
  });

  final String subscriptionId;

  /// Cobro por el que se preguntó (para descartar respuestas obsoletas).
  final DateTime charge;
  final ChargeAnswerAction action;

  /// Fecha elegida para el próximo cobro (null en [ChargeAnswerAction.cancel]).
  final DateTime? next;

  Map<String, Object?> toJson() => {
        'id': subscriptionId,
        'charge': _day(charge),
        'action': action.name,
        if (next != null) 'next': _day(next!),
      };

  factory ChargeAnswer.fromJson(Map<String, Object?> json) => ChargeAnswer(
        subscriptionId: json['id'] as String,
        charge: DateTime.parse(json['charge'] as String),
        action: ChargeAnswerAction.values.byName(json['action'] as String),
        next: json['next'] == null ? null : DateTime.parse(json['next'] as String),
      );

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Datos que viajan dentro de la notificación de confirmación.
@immutable
class ConfirmPayload {
  const ConfirmPayload({required this.subscriptionId, required this.charge, required this.suggestions});

  final String subscriptionId;
  final DateTime charge;
  final List<DateTime> suggestions;

  static const _type = 'confirm';

  String encode() => [
        _type,
        subscriptionId,
        ChargeAnswer._day(charge),
        for (final s in suggestions) ChargeAnswer._day(s),
      ].join('|');

  /// null si el payload no es de confirmación (los demás avisos llevan solo el id).
  static ConfirmPayload? tryDecode(String? payload) {
    final parts = payload?.split('|');
    if (parts == null || parts.length < 3 || parts.first != _type) return null;
    return ConfirmPayload(
      subscriptionId: parts[1],
      charge: DateTime.parse(parts[2]),
      suggestions: [for (final s in parts.skip(3)) DateTime.parse(s)],
    );
  }

  /// Traduce el botón pulsado a una respuesta (null si el botón no aplica).
  ChargeAnswer? answerFor(String? actionId) {
    final action = ChargeAnswerAction.values.asNameMap()[actionId];
    if (action == null) return null;
    final next = switch (action) {
      ChargeAnswerAction.yes => suggestions.firstOrNull,
      ChargeAnswerAction.alt => suggestions.elementAtOrNull(1),
      ChargeAnswerAction.cancel => null,
    };
    if (action != ChargeAnswerAction.cancel && next == null) return null;
    return ChargeAnswer(subscriptionId: subscriptionId, charge: charge, action: action, next: next);
  }
}
