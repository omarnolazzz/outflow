import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../wallet/domain/movement.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../domain/split_movements.dart';
import 'friends_providers.dart';

/// "¿Es este pago?" en Inicio: otra persona repartió un gasto que pagaste tú
/// y tu parte llegó a la wallet junto al pago que ya tenías. "Sí" borra ese
/// pago (queda solo tu parte); "No, es otro" no vuelve a preguntar.
class SplitMatchCards extends ConsumerWidget {
  const SplitMatchCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(splitPaymentMatchesProvider);
    return Column(
      children: [
        for (final m in matches)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SplitMatchCard(match: m),
          ),
      ],
    );
  }
}

class _SplitMatchCard extends ConsumerWidget {
  const _SplitMatchCard({required this.match});
  final SplitPaymentMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = match.expense;
    final creator = e.people[e.createdBy]?.shortName ?? 'Un amigo';
    final title = e.title.isEmpty ? 'un gasto' : e.title;
    final actions = ref.read(walletActionsProvider);

    Future<void> yes(Movement m) async {
      HapticFeedback.mediumImpact();
      await actions.delete(m.id);
      await actions.dismissSplitMatch(e.id);
    }

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('¿Es este pago?', style: AppType.headline),
          const SizedBox(height: 4),
          Text(
            '$creator repartió $title (${Fmt.money(Money(e.totalMinor, e.currency))}), que pagaste tú. '
            'Si es el mismo pago, lo quitamos para no contarlo dos veces: queda tu parte.',
            style: AppType.subhead,
          ),
          const SizedBox(height: 12),
          for (final m in match.candidates.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.title.isEmpty ? 'Gasto' : m.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body),
                        Text(
                          '${Fmt.dateShort(m.date)}${switch (m.origin) {
                            MovementOrigin.applePay => ' · Apple Pay',
                            MovementOrigin.googlePay => ' · Google Pay',
                            _ => '',
                          }} · ${Fmt.money(m.amount)}',
                          style: AppType.footnote.copyWith(color: AppColors.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  PillButton(label: 'Sí', filled: true, onTap: () => yes(m)),
                ],
              ),
            ),
          PillButton(label: 'No, es otro', onTap: () => actions.dismissSplitMatch(e.id)),
        ],
      ),
    );
  }
}
