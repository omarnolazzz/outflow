import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/surface_card.dart';
import 'capture_providers.dart';
import 'review_screen.dart';

/// Inicio: cuántos movimientos automáticos esperan confirmación. Toca → revisión.
class ReviewCard extends ConsumerWidget {
  const ReviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(reviewMovementsProvider).length;
    if (count == 0) return const SizedBox.shrink();
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      onTap: () => openReview(context),
      child: Row(
        children: [
          const Icon(LucideIcons.listChecks, size: 20, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              count == 1 ? '1 movimiento por revisar' : '$count movimientos por revisar',
              style: AppType.subhead.copyWith(fontWeight: FontWeight.w500, color: AppColors.ink),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(LucideIcons.chevronRight, size: 20, color: AppColors.inkTertiary),
        ],
      ),
    );
  }
}
