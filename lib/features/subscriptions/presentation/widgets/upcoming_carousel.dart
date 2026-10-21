import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/motion/app_motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/presentation/widgets/merchant_avatar.dart';
import '../../domain/dashboard_summary.dart';

/// Tarjetas deslizables de próximos cobros y ventanas de cancelación.
///
/// - PageView con `viewportFraction`: la tarjeta siguiente asoma por la
///   derecha, lo que comunica que se puede deslizar sin indicadores extra.
/// - La física de página proyecta la inercia del gesto: un flick corto
///   avanza una tarjeta; la velocidad decide, no la posición.
/// - Haptic de selección al asentarse en cada tarjeta.
class UpcomingCarousel extends StatefulWidget {
  const UpcomingCarousel({
    super.key,
    required this.items,
    required this.merchants,
    required this.onOpen,
  });

  final List<UpcomingItem> items;
  final Map<String, Merchant> merchants;
  final ValueChanged<UpcomingItem> onOpen;

  @override
  State<UpcomingCarousel> createState() => _UpcomingCarouselState();
}

class _UpcomingCarouselState extends State<UpcomingCarousel> {
  late final PageController _controller = PageController(viewportFraction: 0.78);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Padding(
        padding: const EdgeInsets.only(left: 20),
        child: PageView.builder(
          controller: _controller,
          padEnds: false,
          // Las tarjetas que salen por la izquierda se ven hasta el borde de la pantalla.
          clipBehavior: Clip.none,
          itemCount: widget.items.length,
          onPageChanged: (i) {
            if (i != _page) HapticFeedback.selectionClick();
            _page = i;
          },
          itemBuilder: (context, i) {
            final item = widget.items[i];
            final card = Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _UpcomingCard(
                item: item,
                merchant: widget.merchants[item.subscription.merchantId],
                onTap: () => widget.onOpen(item),
              ),
            );
            return Entrance(
              index: i,
              delay: const Duration(milliseconds: 260),
              step: const Duration(milliseconds: 70),
              offset: const Offset(48, 0),
              child: _DepthOnScroll(controller: _controller, index: i, child: card),
            );
          },
        ),
      ),
    );
  }
}

/// Profundidad ligada 1:1 al deslizamiento: la tarjeta en foco a tamaño
/// completo y las vecinas un poco más pequeñas y tenues. Solo escala y
/// opacidad: no provoca relayout.
class _DepthOnScroll extends StatelessWidget {
  const _DepthOnScroll({required this.controller, required this.index, required this.child});
  final PageController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, child) {
        final page = controller.hasClients && controller.position.haveDimensions
            ? controller.page ?? 0
            : 0.0;
        final d = (page - index).abs().clamp(0.0, 1.0);
        return Transform.scale(
          scale: 1 - 0.05 * d,
          alignment: Alignment.centerLeft,
          child: Opacity(opacity: 1 - 0.35 * d, child: child),
        );
      },
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.item, required this.merchant, required this.onTap});

  final UpcomingItem item;
  final Merchant? merchant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = item.subscription;
    final isDeadline = item.kind == UpcomingKind.cancellationDeadline;

    final tag = isDeadline
        ? StatusPill(
            item.daysLeft == 0 ? 'Último día' : 'Cierra ${Fmt.relativeDays(item.daysLeft).toLowerCase()}',
            tone: item.urgency == Urgency.later ? PillTone.neutral : PillTone.danger,
            icon: LucideIcons.hourglass,
          )
        : StatusPill(
            Fmt.relativeDays(item.daysLeft),
            tone: item.urgency == Urgency.now ? PillTone.accent : PillTone.neutral,
          );

    return Pressable(
      onTap: onTap,
      highlight: false,
      scale: 0.97,
      semanticLabel: isDeadline
          ? 'Ventana de cancelación de ${s.name}, cierra el ${Fmt.dateLong(item.date)}'
          : '${s.name}, ${Fmt.money(s.price)}, ${Fmt.dateLong(item.date)}',
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MerchantAvatar(
                  logo: merchant?.logo ?? const MerchantLogo.monogram(),
                  name: s.name,
                  size: 40,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(s.name, style: AppType.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                tag,
              ],
            ),
            const Spacer(),
            if (isDeadline) ...[
              Text('Ventana de cancelación', style: AppType.headline),
              const SizedBox(height: 2),
              Text('Puedes cancelar hasta el ${Fmt.dateShort(item.date)}', style: AppType.caption),
            ] else ...[
              Text(Fmt.money(s.price), style: AppType.amountLarge),
              const SizedBox(height: 4),
              Text(
                '${Fmt.dateShort(item.date)} · ${s.paymentMethod.display}',
                style: AppType.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            _CycleProgress(value: item.cycleProgress),
          ],
        ),
      ),
    );
  }
}

/// Barra de 2px: cuánto del ciclo ha transcurrido. Se rellena al aparecer.
class _CycleProgress extends StatelessWidget {
  const _CycleProgress({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: TweenAnimationBuilder<double>(
          // Se rellena cuando el contenido se revela (no bajo la pantalla de bloqueo).
          tween: Tween(begin: 0, end: EntranceGate.isOpen(context) ? value : 0),
          duration: AppMotion.reduced(context) ? Duration.zero : const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => LinearProgressIndicator(
            value: v,
            minHeight: 4,
            backgroundColor: AppColors.fill,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}
