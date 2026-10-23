import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../domain/movement.dart';

/// "¿Es este pago?": pregunta si un gasto ya registrado es el mismo que se
/// está completando (ticket) o dividiendo. Devuelve `(decidió, elegido)`:
/// `(true, movimiento)` si eligió uno, `(true, null)` con "No, es otro" y
/// `(false, null)` si cerró la hoja sin responder.
Future<(bool decided, Movement? chosen)> askMatchingPayment(
  BuildContext context,
  List<Movement> candidates, {
  String subtitle = 'Ya registraste un gasto parecido. Si es el mismo, lo completamos con el ticket.',
}) async {
  final picked = await showModalBottomSheet<Object>(
    context: context,
    useRootNavigator: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Es este pago?', style: AppType.title2),
            const SizedBox(height: 4),
            Text(subtitle, style: AppType.subhead),
            const SizedBox(height: 14),
            for (final m in candidates.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  onTap: () => Navigator.pop(context, m),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.title.isEmpty ? 'Gasto' : m.title, style: AppType.headline),
                            Text(
                              '${Fmt.dateShort(m.date)}${switch (m.origin) {
                                MovementOrigin.applePay => ' · Apple Pay',
                                MovementOrigin.googlePay => ' · Google Pay',
                                _ => '',
                              }}',
                              style: AppType.footnote,
                            ),
                          ],
                        ),
                      ),
                      Text(Fmt.money(m.amount), style: AppType.amount),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 4),
            PrimaryButton(label: 'No, es otro', secondary: true, onTap: () => Navigator.pop(context, false)),
          ],
        ),
      ),
    ),
  );
  if (picked == null) return (false, null);
  return (true, picked is Movement ? picked : null);
}
