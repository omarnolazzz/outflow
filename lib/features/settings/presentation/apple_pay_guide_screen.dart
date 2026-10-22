import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../wallet/domain/apple_pay_link.dart';
import '../../wallet/domain/movement.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../../wallet/presentation/widgets/movement_sheet.dart';

/// URL que la automatización de Atajos abre al pagar. "Importe", "Comercio" y
/// "Tarjeta" se sustituyen por las variables de la transacción.
const kApplePayShortcutUrl = 'outflow://gasto?importe=Importe&comercio=Comercio&tarjeta=Tarjeta';

const _steps = <(IconData, String, String)>[
  (LucideIcons.layers, 'Abre la app Atajos', 'Ve a la pestaña "Automatización" y toca "Nueva automatización" (+).'),
  (LucideIcons.wallet, 'Elige "Transacción"', 'Selecciona tus tarjetas de Wallet y deja marcadas todas las categorías.'),
  (LucideIcons.zap, 'Marca "Ejecutar inmediatamente"', 'Así se abrirá Outflow solo, sin pedirte confirmación en Atajos.'),
  (LucideIcons.link, 'Añade la acción "Abrir URL"', 'Pega la URL de abajo con el botón Copiar.'),
  (
    LucideIcons.wandSparkles,
    'Cambia las palabras por variables',
    'Toca "Importe" en la URL y elige la variable "Importe" de la transacción; '
        'haz lo mismo con "Comercio" y "Tarjeta".',
  ),
  (LucideIcons.circleCheck, 'Listo', 'La próxima vez que pagues con el iPhone, Outflow se abrirá con el gasto rellenado.'),
];

/// Guía para registrar los pagos de Apple Pay con una automatización de Atajos.
class ApplePayGuideScreen extends ConsumerWidget {
  const ApplePayGuideScreen({super.key});

  void _copy(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: kApplePayShortcutUrl));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('URL copiada. Pégala en la acción "Abrir URL".')));
  }

  void _try(BuildContext context, WidgetRef ref) {
    final currency = ref.read(walletSettingsProvider).value?.currency ?? 'PEN';
    showMovementSheet(
      context,
      draft: MovementDraft(
        amountMinor: 1250,
        currency: currency,
        title: 'Prueba Apple Pay',
        date: ref.read(nowProvider),
        origin: MovementOrigin.applePay,
        note: 'Tarjeta: Ejemplo',
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return SheetScaffold(
      title: 'Apple Pay',
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
          e(Text('Registrar pagos con Apple Pay', textAlign: TextAlign.center, style: AppType.title1)),
          const SizedBox(height: 8),
          e(Text(
            'Cuando pagues con el iPhone, Outflow se abrirá con el importe y el comercio ya puestos. '
            'Solo tendrás que tocar Guardar.',
            textAlign: TextAlign.center,
            style: AppType.subhead,
          )),
          const SizedBox(height: 22),
          e(SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (i, (icon, title, body)) in _steps.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                          child: Text(
                            '${i + 1}',
                            style: AppType.footnote.copyWith(color: AppColors.onAccent, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(icon, size: 16, color: AppColors.inkSecondary),
                                  const SizedBox(width: 6),
                                  Flexible(child: Text(title, style: AppType.headline)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(body, style: AppType.subhead),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          )),
          const SizedBox(height: 16),
          e(SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('URL para la acción "Abrir URL"', style: AppType.footnote.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: ShapeDecoration(
                    color: AppColors.fill,
                    shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: SelectableText(
                    kApplePayShortcutUrl,
                    style: AppType.footnote.copyWith(color: AppColors.ink, fontFamily: 'Menlo'),
                  ),
                ),
                const SizedBox(height: 10),
                PillButton(label: 'Copiar', icon: LucideIcons.copy, onTap: () => _copy(context)),
              ],
            ),
          )),
          const SizedBox(height: 20),
          e(PrimaryButton(
            label: 'Probar',
            icon: const Icon(LucideIcons.play, size: 18, color: AppColors.onAccent),
            onTap: () => _try(context, ref),
          )),
          const SizedBox(height: 8),
          e(Text(
            'Abre la hoja como lo haría el atajo, con un pago de ejemplo.',
            textAlign: TextAlign.center,
            style: AppType.caption,
          )),
        ],
      ),
    );
  }
}
