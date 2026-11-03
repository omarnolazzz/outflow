import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/presentation/widgets/merchant_avatar.dart';
import '../../domain/entities/subscription.dart';
import '../../../wallet/presentation/wallet_providers.dart';
import '../subscription_providers.dart';

/// Tras "Ya la cancelé" en la notificación: ¿llegó a cobrarse este mes?
class CancelQuestionCard extends ConsumerWidget {
  const CancelQuestionCard({super.key, required this.subscription, required this.merchant});

  final Subscription subscription;
  final Merchant? merchant;

  Future<void> _answer(BuildContext context, WidgetRef ref, bool wasCharged) async {
    final actions = ref.read(subscriptionActionsProvider);
    final wallet = ref.read(walletActionsProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final charge = subscription.cancelQuestionCharge!;
    final previous = await actions.resolveCancelQuestion(subscription, wasCharged: wasCharged);
    // "No me cobraron": ese cobro deja de contar como gasto.
    final dropped = wasCharged ? null : await wallet.dropCharge(subscription.id, charge);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(wasCharged ? 'Guardado.' : 'Cobro quitado.'),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () {
            actions.save(previous);
            if (dropped != null) wallet.restore(dropped);
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = subscription;
    final charge = s.cancelQuestionCharge!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MerchantAvatar(logo: merchant?.logo ?? const MerchantLogo.monogram(), name: s.name, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: AppType.headline),
                      Text('Cancelada · cobro previsto el ${Fmt.dateShort(charge)}', style: AppType.footnote),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('¿Te llegaron a cobrar este mes?', style: AppType.title2.copyWith(fontSize: 19)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PillButton(label: 'Sí, me cobraron', filled: true, onTap: () => _answer(context, ref, true)),
                PillButton(label: 'No, la cancelé a tiempo', onTap: () => _answer(context, ref, false)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
