import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/surface_card.dart';
import '../../shell/presentation/app_shell.dart';
import 'friends_format.dart';
import 'friends_providers.dart';

/// Resumen de deudas en Inicio; solo aparece si hay saldos con amigos.
class DebtsCard extends ConsumerWidget {
  const DebtsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = totalsLabel(ref.watch(balancesProvider));
    if (label == null) return const SizedBox.shrink();
    return SurfaceCard(
      onTap: () => ShellScope.maybeOf(context)?.select(AppTab.friends),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          const Icon(LucideIcons.users, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppType.body)),
          const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.inkTertiary),
        ],
      ),
    );
  }
}
