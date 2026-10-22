import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/notifications/data/local_notification_service.dart';

void main() {
  test('en Android la pregunta del cobro lleva los mismos botones que en iPhone', () {
    final two = LocalNotificationService.detailsFor('x', category: 'confirm2').android!;
    expect(two.actions!.map((a) => a.id), ['yes', 'alt', 'cancel']);
    expect(two.actions!.map((a) => a.title), ['Sí, esa fecha', 'Usar la 2ª fecha', 'Ya la cancelé']);
    final one = LocalNotificationService.detailsFor('x', category: 'confirm1').android!;
    expect(one.actions!.map((a) => a.id), ['yes', 'cancel']);
    expect(LocalNotificationService.detailsFor('x').android!.actions, isNull);
  });
}
