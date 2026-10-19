import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/notifications/domain/charge_answer.dart';

void main() {
  final payload = ConfirmPayload(
    subscriptionId: 's1',
    charge: DateTime(2026, 10, 18),
    suggestions: [DateTime(2026, 11, 18), DateTime(2026, 11, 17)],
  );

  test('el payload viaja y vuelve igual', () {
    final back = ConfirmPayload.tryDecode(payload.encode())!;
    expect(back.subscriptionId, 's1');
    expect(back.charge, DateTime(2026, 10, 18));
    expect(back.suggestions, [DateTime(2026, 11, 18), DateTime(2026, 11, 17)]);
  });

  test('los avisos normales (solo id) no son de confirmación', () {
    expect(ConfirmPayload.tryDecode('s1'), isNull);
    expect(ConfirmPayload.tryDecode(null), isNull);
  });

  test('cada botón elige su fecha', () {
    expect(payload.answerFor('yes')!.next, DateTime(2026, 11, 18));
    expect(payload.answerFor('alt')!.next, DateTime(2026, 11, 17));
    expect(payload.answerFor('cancel')!.action, ChargeAnswerAction.cancel);
    expect(payload.answerFor(null), isNull, reason: 'tocar el aviso no es una respuesta');
  });

  test('sin 2ª sugerencia el botón alternativo no responde', () {
    final single = ConfirmPayload(subscriptionId: 's1', charge: DateTime(2026, 10, 18), suggestions: [DateTime(2026, 11, 18)]);
    expect(single.answerFor('alt'), isNull);
  });

  test('la respuesta sobrevive a JSON (bandeja)', () {
    final a = payload.answerFor('alt')!;
    final back = ChargeAnswer.fromJson(a.toJson());
    expect((back.subscriptionId, back.charge, back.action, back.next), ('s1', DateTime(2026, 10, 18), ChargeAnswerAction.alt, DateTime(2026, 11, 17)));
  });
}
