import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../subscriptions/presentation/subscription_providers.dart';
import '../data/local_notification_service.dart';
import '../data/notification_settings_repository.dart';
import '../domain/notification_rule.dart';
import '../domain/reminder_planner.dart';

final notificationServiceProvider = Provider<LocalNotificationService>(
  (ref) => throw UnimplementedError('Se sobrescribe en main()'),
);

final notificationSettingsRepositoryProvider = Provider<NotificationSettingsRepository>(
  (ref) => NotificationSettingsRepository(ref.watch(localStoreProvider)),
);

final globalRuleProvider = StreamProvider<NotificationRule>(
  (ref) => ref.watch(notificationSettingsRepositoryProvider).watchGlobalRule(),
);

final reminderPlannerProvider = Provider<ReminderPlanner>((ref) => const ReminderPlanner());

/// Mantiene los avisos del sistema alineados con los datos: cualquier cambio
/// en suscripciones, regla global o "ahora" (al volver a primer plano)
/// recalcula el plan y lo sincroniza. Se activa con `ref.watch` en la raíz.
final reminderSyncProvider = Provider<void>((ref) {
  final subs = ref.watch(subscriptionsProvider).value;
  final rule = ref.watch(globalRuleProvider).value;
  final now = ref.watch(nowProvider);
  if (subs == null || rule == null) return;

  final plan = ref.read(reminderPlannerProvider).plan(
        subscriptions: subs,
        globalRule: rule,
        now: now,
      );
  ref.read(notificationServiceProvider).sync(plan).catchError((Object e) {
    debugPrint('No se pudieron programar los avisos: $e');
  });
});

/// Pide permiso de avisos (inyectable para pruebas).
final requestNotificationPermissionProvider = Provider<Future<bool> Function()>(
  (ref) => () => ref.read(notificationServiceProvider).requestPermission(),
);
