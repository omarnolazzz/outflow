import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../wallet/data/payment_listener.dart';

/// Android: registrar pagos de Google Pay y bancos leyendo sus notificaciones.
class GooglePayGuideScreen extends ConsumerStatefulWidget {
  const GooglePayGuideScreen({super.key});

  @override
  ConsumerState<GooglePayGuideScreen> createState() => _GooglePayGuideScreenState();
}

class _GooglePayGuideScreenState extends ConsumerState<GooglePayGuideScreen> with WidgetsBindingObserver {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver de los ajustes del teléfono, el estado puede haber cambiado.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await ref.read(paymentListenerProvider).isEnabled();
    if (mounted) setState(() => _enabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);
    final enabled = _enabled ?? false;

    return SheetScaffold(
      title: 'Google Pay',
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.paddingOf(context).bottom + 32),
        children: [
          e(Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
              child: const Icon(LucideIcons.smartphoneNfc, size: 36, color: AppColors.accent),
            ),
          )),
          const SizedBox(height: 14),
          e(Text('Registrar pagos con Google Pay', textAlign: TextAlign.center, style: AppType.title1)),
          const SizedBox(height: 8),
          e(Text(
            'Cuando Google Wallet o tu banco te avisen de un pago, Outflow te mostrará un aviso '
            '"¿Registrar este pago?". Al tocarlo se abre el gasto ya rellenado.',
            textAlign: TextAlign.center,
            style: AppType.subhead,
          )),
          const SizedBox(height: 22),
          e(SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Permiso para leer avisos de pago', style: AppType.headline)),
                    if (_enabled != null)
                      StatusPill(
                        enabled ? 'Activado' : 'Desactivado',
                        tone: enabled ? PillTone.accent : PillTone.neutral,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Solo se leen los avisos de Google Wallet, Google Pay, BCP, Yape, Interbank, BBVA y '
                  'Scotiabank. El resto de tus notificaciones se ignora y nada sale de tu teléfono.',
                  style: AppType.subhead,
                ),
              ],
            ),
          )),
          const SizedBox(height: 20),
          if (_enabled == false)
            e(PrimaryButton(
              label: 'Dar permiso',
              onTap: () {
                HapticFeedback.lightImpact();
                ref.read(paymentListenerProvider).openSettings();
              },
            )),
          if (_enabled == false) ...[
            const SizedBox(height: 8),
            e(Text(
              'En la lista, activa "Outflow · pagos" y vuelve aquí.',
              textAlign: TextAlign.center,
              style: AppType.caption,
            )),
          ],
        ],
      ),
    );
  }
}
