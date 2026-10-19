import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/utils/formatters.dart';
import '../domain/reminder_planner.dart';

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

  static const _channelId = 'outflow_reminders';
  static const _channelName = 'Recordatorios de cobro';

  /// Ids de suscripción de las notificaciones que el usuario toca.
  Stream<String> get taps => _taps.stream;

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
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_outflow'),
        // El permiso se pide en el momento oportuno, no al abrir la app.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final id = r.payload;
        if (id != null && id.isNotEmpty) _taps.add(id);
      },
    );
    _ready = true;
  }

  /// Payload de la notificación que abrió la app en frío, si la hubo.
  Future<String?> launchPayload() async {
    if (_unsupported) return null;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details!.notificationResponse?.payload;
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
        notificationDetails: _details(copy.body),
        // Inexacto: no requiere el permiso SCHEDULE_EXACT_ALARM y un recordatorio
        // de cobro no necesita precisión de segundos.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: r.subscription.id,
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

  NotificationDetails _details(String? body) => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Avisos antes de cada cobro y del cierre de la ventana de cancelación',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          styleInformation: body == null ? null : BigTextStyleInformation(body),
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: const DarwinNotificationDetails(threadIdentifier: _channelId),
      );

  Future<void> dispose() => _taps.close();
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
    };
  }
}
