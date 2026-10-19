import '../../../core/storage/local_store.dart';
import '../domain/notification_rule.dart';

/// Guarda la regla global de recordatorios en la caja de ajustes.
class NotificationSettingsRepository {
  NotificationSettingsRepository(this._store);

  final LocalStore _store;
  static const _id = 'notifications.globalRule';

  Stream<NotificationRule> watchGlobalRule() => _store
      .watchAll(LocalStore.settingsBox)
      .map((_) => _readGlobal())
      .distinct((a, b) => a.toJson().toString() == b.toJson().toString());

  NotificationRule _readGlobal() {
    final json = _store.read(LocalStore.settingsBox, _id);
    return json == null ? NotificationRule.defaults : NotificationRule.fromJson(json);
  }

  Future<void> saveGlobalRule(NotificationRule rule) =>
      _store.write(LocalStore.settingsBox, _id, rule.toJson());
}
