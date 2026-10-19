import 'package:meta/meta.dart';

/// Regla de recordatorios. Existe una global y cada suscripción puede
/// sobrescribirla con la suya.
///
/// Ejemplos:
/// - "Avisar 10 días antes, todos los días"  → leadDays 10, repeatEveryDays 1
/// - "Avisar 10 días antes, dejando 2 días entre avisos" → leadDays 10, repeatEveryDays 3
///   (días 10, 7, 4, 1 antes del cobro)
/// - Alertas puntuales extra → customOffsets {30, 2}
@immutable
class NotificationRule {
  const NotificationRule({
    this.enabled = true,
    this.leadDays = 3,
    this.repeatEveryDays = 1,
    this.customOffsets = const {},
    this.remindOnChargeDay = true,
    this.remindCancellationDeadline = true,
    this.deadlineLeadDays = 1,
    this.hour = 9,
    this.minute = 0,
  })  : assert(leadDays >= 0),
        assert(repeatEveryDays >= 1);

  static const defaults = NotificationRule();

  final bool enabled;

  /// Cuántos días antes del cobro empieza la serie de avisos (0 = sin serie).
  final int leadDays;

  /// Cadencia de la serie: 1 = diario, 2 = un día sí y uno no, 3 = deja 2 días…
  final int repeatEveryDays;

  /// Avisos puntuales adicionales, en días antes del cobro.
  final Set<int> customOffsets;

  final bool remindOnChargeDay;

  /// Avisar antes de que cierre la ventana de cancelación de la suscripción.
  final bool remindCancellationDeadline;
  final int deadlineLeadDays;

  /// Hora local del aviso.
  final int hour;
  final int minute;

  /// Días antes del cobro en los que hay aviso, de mayor a menor (0 = día del cobro).
  List<int> get chargeOffsets {
    final offsets = <int>{...customOffsets};
    for (var d = leadDays; d >= 1; d -= repeatEveryDays) {
      offsets.add(d);
    }
    if (remindOnChargeDay) offsets.add(0);
    return offsets.where((d) => d >= 0).toList()..sort((a, b) => b.compareTo(a));
  }

  NotificationRule copyWith({
    bool? enabled,
    int? leadDays,
    int? repeatEveryDays,
    Set<int>? customOffsets,
    bool? remindOnChargeDay,
    bool? remindCancellationDeadline,
    int? deadlineLeadDays,
    int? hour,
    int? minute,
  }) =>
      NotificationRule(
        enabled: enabled ?? this.enabled,
        leadDays: leadDays ?? this.leadDays,
        repeatEveryDays: repeatEveryDays ?? this.repeatEveryDays,
        customOffsets: customOffsets ?? this.customOffsets,
        remindOnChargeDay: remindOnChargeDay ?? this.remindOnChargeDay,
        remindCancellationDeadline: remindCancellationDeadline ?? this.remindCancellationDeadline,
        deadlineLeadDays: deadlineLeadDays ?? this.deadlineLeadDays,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'leadDays': leadDays,
        'repeatEveryDays': repeatEveryDays,
        'customOffsets': customOffsets.toList()..sort(),
        'remindOnChargeDay': remindOnChargeDay,
        'remindCancellationDeadline': remindCancellationDeadline,
        'deadlineLeadDays': deadlineLeadDays,
        'hour': hour,
        'minute': minute,
      };

  factory NotificationRule.fromJson(Map<String, Object?> json) => NotificationRule(
        enabled: json['enabled'] as bool? ?? true,
        leadDays: (json['leadDays'] as num?)?.toInt() ?? 3,
        repeatEveryDays: (json['repeatEveryDays'] as num?)?.toInt() ?? 1,
        customOffsets: {
          for (final o in (json['customOffsets'] as List? ?? const [])) (o as num).toInt(),
        },
        remindOnChargeDay: json['remindOnChargeDay'] as bool? ?? true,
        remindCancellationDeadline: json['remindCancellationDeadline'] as bool? ?? true,
        deadlineLeadDays: (json['deadlineLeadDays'] as num?)?.toInt() ?? 1,
        hour: (json['hour'] as num?)?.toInt() ?? 9,
        minute: (json['minute'] as num?)?.toInt() ?? 0,
      );
}
