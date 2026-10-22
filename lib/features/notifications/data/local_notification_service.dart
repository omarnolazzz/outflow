import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/utils/formatters.dart';
import '../domain/charge_answer.dart';
import '../domain/reminder_planner.dart';
import 'charge_answer_inbox.dart';

/// Envoltorio de `flutter_local_notifications`.
///
/// Estrategia: en lugar de calcular ids por suscripción y cancelar
/// selectivamente, cada sincronización reemplaza el conjunto completo de
/// avisos pendientes por el plan actual (ventana rodante de ~2 meses,
/// máximo 60 avisos — iOS admite 64). Es idempotente: llamarlo dos veces
/// con el mismo plan deja el mismo resultado.
class LocalNotificationService {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<String>.broadcast();
  final _answers = StreamController<ChargeAnswer>.broadcast();

  static const _channelId = 'outflow_reminders';
  static const _channelName = 'Recordatorios de cobro';

  /// Categorías de iOS para la pregunta del cobro. Los textos de los botones
  /// se registran al iniciar y no pueden cambiar por aviso: las fechas van en
  /// el texto de la notificación.
  static const _confirmTwo = 'confirm2';
  static const _confirmOne = 'confirm1';
  static const _unlock = {DarwinNotificationActionOption.authenticationRequired};
  static final _yes = DarwinNotificationAction.plain('yes', 'Sí, esa fecha', options: _unlock);
  static final _alt = DarwinNotificationAction.plain('alt', 'Usar la 2ª fecha', options: _unlock);
  static final _cancel = DarwinNotificationAction.plain('cancel', 'Ya la cancelé',
      options: {..._unlock, DarwinNotificationActionOption.destructive});

  /// Ids de suscripción de las notificaciones que el usuario toca.
  Stream<String> get taps => _taps.stream;

  /// Botones de la pregunta del cobro pulsados con la app abierta.
  Stream<ChargeAnswer> get answers => _answers.stream;

  bool _ready = false;

  /// En web (vista previa en el navegador) no hay notificaciones locales.
  static bool get _unsupported => kIsWeb;

  Future<void> init() async {
    if (_ready || _unsupported) return;
    tz_data.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      debugPrint('Zona horaria no disponible, se usa UTC: $e');
    }

    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('ic_stat_outflow'),
        // El permiso se pide en el momento oportuno, no al abrir la app.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(_confirmTwo, actions: [_yes, _alt, _cancel]),
            DarwinNotificationCategory(_confirmOne, actions: [_yes, _cancel]),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final confirm = ConfirmPayload.tryDecode(r.payload);
        final answer = confirm?.answerFor(r.actionId);
        if (answer != null) return _answers.add(answer);
        final id = confirm?.subscriptionId ?? r.payload;
        if (id != null && id.isNotEmpty) _taps.add(id);
      },
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationResponse,
    );
    _ready = true;
  }

  /// Payload de la notificación que abrió la app en frío, si la hubo.
  Future<String?> launchPayload() async {
    if (_unsupported) return null;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final payload = details!.notificationResponse?.payload;
    return ConfirmPayload.tryDecode(payload)?.subscriptionId ?? payload;
  }

  /// Pide permiso (Android 13+ / iOS). Llamar cuando el usuario active o
  /// cree su primer recordatorio: así entiende por qué se le pide.
  Future<bool> requestPermission() async {
    if (_unsupported) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    return false;
  }

  List<PlannedReminder>? _queued;
  Future<void>? _running;

  /// Reemplaza todos los avisos pendientes por [plan].
  ///
  /// Las llamadas se serializan y, si llegan varias mientras una corre, solo
  /// se aplica la más reciente (los cambios rápidos no entrelazan
  /// cancelaciones y programaciones).
  Future<void> sync(List<PlannedReminder> plan) {
    _queued = plan;
    return _running ??= _drain().whenComplete(() => _running = null);
  }

  Future<void> _drain() async {
    while (_queued != null) {
      final plan = _queued!;
      _queued = null;
      await _apply(plan);
    }
  }

  Future<void> _apply(List<PlannedReminder> plan) async {
    if (_unsupported) return;
    await init();
    await _plugin.cancelAllPendingNotifications();

    for (var i = 0; i < plan.length; i++) {
      final r = plan[i];
      final copy = ReminderCopy.of(r);
      await _plugin.zonedSchedule(
        id: i,
        title: copy.title,
        body: copy.body,
        scheduledDate: tz.TZDateTime.from(r.fireAt, tz.local),
        notificationDetails: _details(
          copy.body,
          category: r.kind != ReminderKind.confirmCharge
              ? null
              : (r.suggestions.length > 1 ? _confirmTwo : _confirmOne),
        ),
        // Inexacto: no requiere el permiso SCHEDULE_EXACT_ALARM y un recordatorio
        // de cobro no necesita precisión de segundos.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: r.kind == ReminderKind.confirmCharge
            ? ConfirmPayload(subscriptionId: r.subscription.id, charge: r.chargeDate, suggestions: r.suggestions)
                .encode()
            : r.subscription.id,
      );
    }
  }

  Future<void> showTest() async {
    if (_unsupported) return;
    await init();
    await _plugin.show(
      id: 9999,
      title: 'Así se verán tus avisos',
      body: 'Netflix · \$15.49 se cobra en 3 días.',
      notificationDetails: _details(null),
    );
  }

  NotificationDetails _details(String? body, {String? category}) => detailsFor(body, category: category);

  /// Detalles por plataforma. En Android los botones van en cada aviso (en
  /// iPhone salen de la categoría registrada al iniciar).
  @visibleForTesting
  static NotificationDetails detailsFor(String? body, {String? category}) {
    // Sin interfaz: la respuesta se guarda en segundo plano, como en iPhone.
    AndroidNotificationAction action(String id, String title) =>
        AndroidNotificationAction(id, title, showsUserInterface: false, cancelNotification: true);
    final actions = switch (category) {
      _confirmTwo => [
          action('yes', 'Sí, esa fecha'),
          action('alt', 'Usar la 2ª fecha'),
          action('cancel', 'Ya la cancelé'),
        ],
      _confirmOne => [action('yes', 'Sí, esa fecha'), action('cancel', 'Ya la cancelé')],
      _ => null,
    };
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Avisos antes de cada cobro y del cierre de la ventana de cancelación',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: body == null ? null : BigTextStyleInformation(body),
        category: AndroidNotificationCategory.reminder,
        actions: actions,
      ),
      iOS: DarwinNotificationDetails(threadIdentifier: _channelId, categoryIdentifier: category),
    );
  }

  Future<void> dispose() async {
    await _taps.close();
    await _answers.close();
  }
}

/// Texto de cada aviso: directo, con el dato que importa primero.
class ReminderCopy {
  const ReminderCopy(this.title, this.body);
  final String title;
  final String body;

  factory ReminderCopy.of(PlannedReminder r) {
    final s = r.subscription;
    final amount = Fmt.money(s.price);
    return switch (r.kind) {
      ReminderKind.chargeDay => ReminderCopy(
          '${s.name} se cobra hoy',
          '$amount con ${s.paymentMethod.display}.',
        ),
      ReminderKind.upcomingCharge => ReminderCopy(
          '${s.name} · ${Fmt.relativeDays(r.daysBefore).toLowerCase()}',
          '$amount el ${Fmt.dateShort(r.chargeDate)} con ${s.paymentMethod.display}.',
        ),
      ReminderKind.cancellationDeadline => ReminderCopy(
          r.daysBefore == 0
              ? 'Último día para cancelar ${s.name}'
              : 'Quedan ${Fmt.days(r.daysBefore)} para cancelar ${s.name}',
          'La ventana de cancelación cierra el ${Fmt.dateShort(r.chargeDate)}.',
        ),
      ReminderKind.confirmCharge => ReminderCopy(
          '${s.name} · ¿Próximo cobro el ${Fmt.dateShort(r.suggestions.first)}?',
          r.suggestions.length > 1
              ? 'Otra opción: ${Fmt.dateShort(r.suggestions[1])}. Mantén pulsado para responder.'
              : 'Mantén pulsado para responder.',
        ),
    };
  }
}
