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
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/presentation/merchant_providers.dart';
import '../../../merchants/presentation/widgets/merchant_avatar.dart';
import '../../domain/charge_pattern.dart';
import '../../domain/charge_schedule.dart';
import '../../domain/entities/subscription.dart';
import '../../../wallet/presentation/wallet_providers.dart';
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
    useRootNavigator: true,
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
    final previous = await actions.cancelAfterCharge(s, pending, wasCharged: result.wasCharged);
    final wallet = ref.read(walletActionsProvider);
    // "No me cobraron": ese cobro deja de contar como gasto.
    final dropped = result.wasCharged ? null : await wallet.dropCharge(s.id, pending);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.wasCharged
              ? 'Cancelada. El último cobro queda registrado.'
              : 'Cancelada a tiempo. Ya no recibirás avisos.',
        ),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () {
            actions.save(previous);
            if (dropped != null) wallet.restore(dropped);
          },
        ),
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
    : cancelled = false,
      wasCharged = true;
  const _SheetResult.cancelled({required this.wasCharged})
      : chargedOn = null,
        next = null,
        pattern = null,
        cancelled = true;

  final DateTime? chargedOn;
  final DateTime? next;
  final ChargePattern? pattern;
  final bool cancelled;

  /// Al cancelar: ¿llegó a cobrarse este último cobro?
  final bool wasCharged;
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

  /// Tras "Ya la cancelé": falta saber si el último cobro llegó a pasar.
  bool _askingCancel = false;

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

    if (_askingCancel) return _CancelQuestion(name: _s.name);

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
                  Expanded(child: Text('Confirma el cobro de ${_s.name}', style: AppType.title2)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            e(Text('¿Cuándo se cobró?', style: AppType.footnote.copyWith(fontWeight: FontWeight.w600))),
            const SizedBox(height: 8),
            e(
              Pressable(
                onTap: _pickChargedOn,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: ShapeDecoration(
                    color: AppColors.fill,
                    shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(14)),
                  ),
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
            e(Text('¿Cuándo será el próximo?', style: AppType.footnote.copyWith(fontWeight: FontWeight.w600))),
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
            e(PrimaryButton(label: 'Confirmar', onTap: _next == null ? null : _confirm)),
            const SizedBox(height: 4),
            e(
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _askingCancel = true),
                  child: Text('Ya la cancelé', style: AppType.callout.copyWith(color: AppColors.danger, fontWeight: FontWeight.w600)),
                ),
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
          color: selected ? AppColors.accentSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.accent : AppColors.separator, width: selected ? 1.5 : 1),
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
                    color: selected ? AppColors.accent : AppColors.separator,
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

/// Segundo paso de "Ya la cancelé": ¿llegó a cobrarse el último cobro?
class _CancelQuestion extends StatelessWidget {
  const _CancelQuestion({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Entrance(child: Text('¿Te llegaron a cobrar este mes?', style: AppType.title2)),
              const SizedBox(height: 6),
              Entrance(
                index: 1,
                child: Text(
                  'Así sabremos si el último cobro de $name se registra en tu historial.',
                  style: AppType.subhead,
                ),
              ),
              const SizedBox(height: 20),
              Entrance(
                index: 2,
                child: PrimaryButton(
                  label: 'Sí, me cobraron',
                  onTap: () => Navigator.pop(context, const _SheetResult.cancelled(wasCharged: true)),
                ),
              ),
              const SizedBox(height: 10),
              Entrance(
                index: 3,
                child: PrimaryButton(
                  label: 'No, la cancelé a tiempo',
                  secondary: true,
                  onTap: () => Navigator.pop(context, const _SheetResult.cancelled(wasCharged: false)),
                ),
              ),
            ],
          ),
        ),
      );
}
