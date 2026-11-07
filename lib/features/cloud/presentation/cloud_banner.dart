import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/surface_card.dart';
import 'cloud_sync.dart';

/// Inicio: la nube no respondió o negó el permiso. Tocar reintenta. Solo se ve
/// en [CloudSyncState.unavailable] (en la vista previa la sincronización está inactiva).
class CloudBanner extends ConsumerWidget {
  const CloudBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(cloudSyncStateProvider) != CloudSyncState.unavailable) return const SizedBox.shrink();
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      onTap: () => ref.read(cloudSyncProvider.notifier).retry().ignore(),
      child: Row(
        children: [
          const Icon(LucideIcons.cloudOff, size: 20, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tu información aún no se está guardando en la nube',
              style: AppType.subhead.copyWith(fontWeight: FontWeight.w500, color: AppColors.ink),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(LucideIcons.refreshCw, size: 18, color: AppColors.inkTertiary),
        ],
      ),
    );
  }
}
