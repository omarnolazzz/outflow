import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/surface_card.dart';
import '../../wallet/domain/movement.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../../wallet/presentation/widgets/movement_row.dart';
import '../../wallet/presentation/widgets/movement_sheet.dart';
import '../domain/process_captures.dart';
import 'capture_providers.dart';

/// Abre la revisión sobre la barra de pestañas.
Future<void> openReview(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const ReviewScreen()));

/// Lo guardado automáticamente, para confirmar, corregir o borrar.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  Future<void> _confirm(WidgetRef ref, Movement m) async {
    HapticFeedback.mediumImpact();
    await ref.read(walletActionsProvider).save(m.copyWith(
          needsReview: false,
          // Confirmado, ya no es un posible duplicado sino un pago real.
          note: m.note == kDuplicateNote ? '' : null,
        ));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Movement m) async {
    final actions = ref.read(walletActionsProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final deleted = await actions.delete(m.id);
    if (deleted == null) return;
    HapticFeedback.heavyImpact();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Movimiento borrado.'),
        action: SnackBarAction(label: 'Deshacer', onPressed: () => actions.restore(deleted)),
      ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(reviewMovementsProvider);
    final categories = ref.watch(categoryIndexProvider);
    return SheetScaffold(
      title: 'Por revisar',
      child: items.isEmpty
          ? Center(child: Text('Nada por revisar.', style: AppType.subhead))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final m = items[i];
                return SurfaceCard(
                  key: ValueKey(m.id),
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MovementRow(movement: m, category: categories[m.categoryId], showDate: true),
                      if (m.note.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                          child: Text(m.note, style: AppType.footnote),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        // Con letra grande, los botones bajan de línea.
                        child: Wrap(
                          children: [
                            TextButton(
                              onPressed: () => _confirm(ref, m),
                              style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                              child: const Text('Confirmar'),
                            ),
                            // La hoja de gasto no sirve para una transferencia.
                            if (!m.isTransferOrAdjustment)
                              TextButton(
                                onPressed: () => showMovementSheet(context, editing: m),
                                style: TextButton.styleFrom(foregroundColor: AppColors.ink),
                                child: const Text('Editar'),
                              ),
                            TextButton(
                              onPressed: () => _delete(context, ref, m),
                              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                              child: const Text('Borrar'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
