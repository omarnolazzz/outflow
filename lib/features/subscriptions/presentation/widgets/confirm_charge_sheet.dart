import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/domain/billing_cycle.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/notion_widgets.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/presentation/merchant_providers.dart';
import '../../../merchants/presentation/widgets/merchant_avatar.dart';
import '../../domain/charge_pattern.dart';
import '../../domain/charge_schedule.dart';
import '../../domain/entities/subscription.dart';
import '../subscription_providers.dart';

/// Abre la pregunta detallada del cobro [pending] y aplica la respuesta,
/// con "Deshacer" en la confirmación.
Future<void> showConfirmChargeSheet(
  BuildContext context,
  WidgetRef ref,
  Subscription s,
  DateTime pending,
) async {
  final result = await showModalBottomSheet<_SheetResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ConfirmChargeSheet(subscription: s, pending: pending),
  );
  if (result == null || !context.mounted) return;
  await _applyResult(context, ref, s, pending, result);
}

/// Confirma con la primera sugerencia (botón "Sí" de la tarjeta del dashboard).
Future<void> confirmFirstSuggestion(BuildContext context, WidgetRef ref, Subscription s, DateTime pending) {
  final first = suggestNext(s, pending).first;
  return _applyResult(
    context,
    ref,
    s,
    pending,
    _SheetResult(chargedOn: pending, next: first.date, pattern: first.pattern),
  );
}

Future<void> _applyResult(
  BuildContext context,
  WidgetRef ref,
  Subscription s,
  DateTime pending,
  _SheetResult result,
) async {
  final actions = ref.read(subscriptionActionsProvider);
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  if (result.cancelled) {
    HapticFeedback.mediumImpact();
    final previous = await actions.setStatus(s, SubscriptionStatus.cancelled);
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Marcada como cancelada. Ya no recibirás avisos.'),
        action: SnackBarAction(label: 'Deshacer', onPressed: () => actions.save(previous)),
      ),
    );
    return;
  }
  HapticFeedback.lightImpact();
  final previous = await actions.confirmCharge(
    s,
    pending: pending,
    chargedOn: result.chargedOn!,
    next: result.next!,
    pattern: result.pattern,
  );
  messenger.showSnackBar(
    SnackBar(
      content: Text('${s.name}: próximo cobro el ${Fmt.dateShort(result.next!)}.'),
      action: SnackBarAction(label: 'Deshacer', onPressed: () => actions.save(previous)),
    ),
  );
}

class _SheetResult {
  const _SheetResult({required DateTime this.chargedOn, required DateTime this.next, this.pattern})
    : cancelled = false;
  const _SheetResult.cancelled() : chargedOn = null, next = null, pattern = null, cancelled = true;

  final DateTime? chargedOn;
  final DateTime? next;
  final ChargePattern? pattern;
  final bool cancelled;
}

class _ConfirmChargeSheet extends ConsumerStatefulWidget {
  const _ConfirmChargeSheet({required this.subscription, required this.pending});
  final Subscription subscription;
  final DateTime pending;

  @override
  ConsumerState<_ConfirmChargeSheet> createState() => _ConfirmChargeSheetState();
}

class _ConfirmChargeSheetState extends ConsumerState<_ConfirmChargeSheet> {
  late DateTime _chargedOn = widget.pending;

  /// Índice de la sugerencia elegida, o null si se eligió una fecha propia.
  int? _selected = 0;
  DateTime? _custom;

  Subscription get _s => widget.subscription;
  List<ChargeSuggestion> get _suggestions => suggestNext(_s, _chargedOn);

  DateTime? get _next => _selected != null ? _suggestions[_selected!].date : _custom;

  Future<void> _pickChargedOn() async {
    final today = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _chargedOn,
      firstDate: widget.pending.subtract(const Duration(days: 20)),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() {
      _chargedOn = dateOnly(picked);
      if (_selected != null) _selected = 0;
    });
  }

  Future<void> _pickCustom() async {
    final base = _custom ?? _suggestions.first.date;
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: _chargedOn.add(const Duration(days: 1)),
      lastDate: _chargedOn.add(const Duration(days: 400)),
    );
    if (picked == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _custom = dateOnly(picked);
      _selected = null;
    });
  }

  void _confirm() {
    final next = _next;
    if (next == null) return;
    Navigator.pop(
      context,
      _SheetResult(
        chargedOn: _chargedOn,
        next: next,
        pattern: _selected == null ? null : _suggestions[_selected!].pattern,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final merchant = ref.watch(merchantIndexProvider)[_s.merchantId];
    final suggestions = _suggestions;
    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            e(
              Row(
                children: [
                  MerchantAvatar(
                    logo: merchant?.logo ?? const MerchantLogo.monogram(),
                    name: _s.name,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Confirma el cobro de ${_s.name}', style: AppType.headline)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            e(Text('¿Cuándo se cobró?', style: AppType.section)),
            const SizedBox(height: 8),
            e(
              Pressable(
                onTap: _pickChargedOn,
                child: NotionBlock(
                  color: AppColors.surfaceMuted,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.calendarCheck, size: 16, color: AppColors.inkTertiary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: AppMotion.short,
                          layoutBuilder: (current, previous) =>
                              Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                          child: Text(
                            _capitalize(Fmt.dateLong(_chargedOn)),
                            key: ValueKey(_chargedOn),
                            style: AppType.bodyStrong,
                          ),
                        ),
                      ),
                      Text('Cambiar', style: AppType.caption),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            e(Text('¿Cuándo será el próximo?', style: AppType.section)),
            const SizedBox(height: 8),
            for (var i = 0; i < suggestions.length; i++)
              e(
                _OptionTile(
                  selected: _selected == i,
                  title: _capitalize(Fmt.dateLong(suggestions[i].date)),
                  subtitle: i == 0 ? '${suggestions[i].label} · más probable' : suggestions[i].label,
                  onTap: () => setState(() => _selected = i),
                ),
              ),
            e(
              _OptionTile(
                selected: _selected == null,
                title: _custom == null ? 'Otra fecha…' : _capitalize(Fmt.dateLong(_custom!)),
                subtitle: _custom == null ? 'Elegir en el calendario' : 'Fecha elegida',
                icon: LucideIcons.calendar,
                onTap: _pickCustom,
              ),
            ),
            const SizedBox(height: 20),
            e(
              Row(
                children: [
                  Expanded(
                    child: OutlineAction(
                      label: 'Confirmar',
                      filled: true,
                      onTap: _next == null ? null : _confirm,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlineAction(
                    label: 'Ya la cancelé',
                    danger: true,
                    onTap: () => Navigator.pop(context, const _SheetResult.cancelled()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Opción seleccionable con indicador circular animado.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Pressable(
      onTap: onTap,
      haptic: true,
      highlight: false,
      scale: 0.98,
      child: AnimatedContainer(
        duration: AppMotion.short,
        curve: AppMotion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.callout : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppColors.ink : AppColors.border, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            SelectionPop(
              active: selected,
              amount: 0.15,
              child: AnimatedContainer(
                duration: AppMotion.short,
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.ink : AppColors.border,
                    width: selected ? 5.5 : 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppType.bodyStrong),
                  Text(subtitle, style: AppType.caption),
                ],
              ),
            ),
            if (icon != null) Icon(icon, size: 16, color: AppColors.inkTertiary),
          ],
        ),
      ),
    ),
  );
}
