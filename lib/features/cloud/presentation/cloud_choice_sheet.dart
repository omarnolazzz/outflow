import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/primary_button.dart';
import '../../account/presentation/session_controller.dart';
import 'cloud_sync.dart';

/// Abre la hoja de elegir sobre la app cuando la nube pide una decisión y la
/// sesión está abierta (sobre la pantalla de bloqueo no se podría actuar).
/// Sin decidir, vuelve a abrirse en el próximo arranque.
class CloudChoiceTrigger extends ConsumerStatefulWidget {
  const CloudChoiceTrigger({super.key, required this.navigator, required this.child});

  final GlobalKey<NavigatorState> navigator;
  final Widget child;

  @override
  ConsumerState<CloudChoiceTrigger> createState() => _CloudChoiceTriggerState();
}

class _CloudChoiceTriggerState extends ConsumerState<CloudChoiceTrigger> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    // Puede haber una decisión pendiente desde antes de montar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });
  }

  void _check() {
    if (_open) return;
    if (ref.read(cloudSyncStateProvider) != CloudSyncState.needsChoice) return;
    if (ref.read(sessionControllerProvider) is! Ready) return;
    _open = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final context = widget.navigator.currentContext;
      if (context != null && mounted && ref.read(cloudSyncStateProvider) == CloudSyncState.needsChoice) {
        await showCloudChoiceSheet(context);
      }
      _open = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(cloudSyncStateProvider, (_, _) => _check());
    ref.listen(sessionControllerProvider, (_, _) => _check());
    return widget.child;
  }
}

/// Hoja que no se cierra sola: la decisión es obligatoria.
Future<void> showCloudChoiceSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.background,
      builder: (_) => const PopScope(canPop: false, child: _CloudChoiceSheet()),
    );

class _CloudChoiceSheet extends ConsumerStatefulWidget {
  const _CloudChoiceSheet();

  @override
  ConsumerState<_CloudChoiceSheet> createState() => _CloudChoiceSheetState();
}

class _CloudChoiceSheetState extends ConsumerState<_CloudChoiceSheet> {
  bool _busy = false;
  bool _confirming = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      // Si siguió pendiente de decidir (la acción no hizo nada), vuelve a poder elegir.
      if (mounted && ref.read(cloudSyncStateProvider) == CloudSyncState.needsChoice) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _cloudOnly() async {
    _confirming = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Usar solo los de la nube?'),
        content: const Text(
          'Se descartarán los datos de este teléfono que no estén en tu cuenta. No se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar y usar la nube', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    _confirming = false;
    if (ok != true || !mounted) return;
    await _run(ref.read(cloudSyncProvider.notifier).chooseCloudOnly);
  }

  @override
  Widget build(BuildContext context) {
    // Hecho (en vivo) o fallido (el aviso de Inicio toma el relevo): la hoja se va.
    ref.listen(cloudSyncStateProvider, (_, next) {
      if (next == CloudSyncState.live || next == CloudSyncState.unavailable || next == CloudSyncState.idle) {
        // Quita la hoja aunque el diálogo de confirmar esté encima.
        final route = ModalRoute.of(context);
        if (_confirming) {
          _confirming = false;
          Navigator.of(context).pop();
        }
        if (route != null && route.isActive) Navigator.of(context).removeRoute(route);
      }
    });
    final working = _busy || ref.watch(cloudSyncStateProvider) == CloudSyncState.syncing;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Este teléfono tiene datos que no están en tu cuenta', style: AppType.title2),
            const SizedBox(height: 10),
            Text(
              'Puedes unirlos con los de tu cuenta o quedarte solo con los de la nube.',
              style: AppType.subhead,
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Unir',
              loading: working,
              onTap: () => _run(ref.read(cloudSyncProvider.notifier).chooseMerge),
            ),
            const SizedBox(height: 10),
            PrimaryButton(
              label: 'Usar solo los de la nube',
              secondary: true,
              onTap: working ? null : _cloudOnly,
            ),
          ],
        ),
      ),
    );
  }
}
