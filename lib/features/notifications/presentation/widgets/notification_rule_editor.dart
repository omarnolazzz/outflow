import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/motion/app_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/notion_widgets.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../subscriptions/domain/entities/subscription.dart';
import '../../domain/notification_rule.dart';

/// Resumen de una regla en una línea: "Diario desde 3 días antes · 09:00".
String describeRule(NotificationRule r) {
  if (!r.enabled) return 'Desactivados';
  final parts = <String>[];
  if (r.leadDays > 0) {
    parts.add(r.repeatEveryDays == 1
        ? 'Diario desde ${Fmt.days(r.leadDays)} antes'
        : 'Cada ${r.repeatEveryDays} días desde ${Fmt.days(r.leadDays)} antes');
  }
  if (r.customOffsets.isNotEmpty) parts.add('+${r.customOffsets.length} extra');
  if (r.remindOnChargeDay) parts.add('día del cobro');
  if (parts.isEmpty) return 'Sin avisos de cobro';
  return '${parts.join(', ')} · ${Fmt.time(r.hour, r.minute)}';
}

/// Editor completo de una [NotificationRule]. Sin estado propio: la regla
/// entra por props y cada cambio sale por [onChanged].
class NotificationRuleEditor extends StatelessWidget {
  const NotificationRuleEditor({super.key, required this.rule, required this.onChanged});

  final NotificationRule rule;
  final ValueChanged<NotificationRule> onChanged;

  static const _presetOffsets = [1, 2, 3, 5, 7, 14, 30];

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: rule.hour, minute: rule.minute),
      initialEntryMode: TimePickerEntryMode.inputOnly,
    );
    if (picked != null) onChanged(rule.copyWith(hour: picked.hour, minute: picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final r = rule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SwitchRow(
          icon: LucideIcons.bellRing,
          label: 'Recordatorios',
          value: r.enabled,
          onChanged: (v) => onChanged(r.copyWith(enabled: v)),
        ),
        // Las opciones se pliegan (no desaparecen de golpe) al desactivar.
        AnimatedSize(
          duration: AppMotion.medium,
          curve: AppMotion.ease,
          alignment: Alignment.topCenter,
          child: !r.enabled
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    _StepperRow(
                      icon: LucideIcons.calendarClock,
                      label: 'Empezar a avisar',
                      value: r.leadDays,
                      min: 0,
                      max: 60,
                      format: (v) => v == 0 ? 'No' : '${Fmt.days(v)} antes',
                      // La frecuencia nunca puede superar la antelación.
                      onChanged: (v) => onChanged(r.copyWith(
                        leadDays: v,
                        repeatEveryDays: r.repeatEveryDays.clamp(1, v < 1 ? 1 : v),
                      )),
                    ),
                    if (r.leadDays > 1)
                      _StepperRow(
                        icon: LucideIcons.repeat,
                        label: 'Frecuencia',
                        caption: r.repeatEveryDays == 1
                            ? 'Un aviso cada día'
                            : 'Deja ${Fmt.days(r.repeatEveryDays - 1)} entre avisos',
                        value: r.repeatEveryDays,
                        min: 1,
                        max: r.leadDays,
                        format: (v) => v == 1 ? 'Diario' : 'Cada $v días',
                        onChanged: (v) => onChanged(r.copyWith(repeatEveryDays: v)),
                      ),
                    _SwitchRow(
                      icon: LucideIcons.calendar,
                      label: 'El día del cobro',
                      value: r.remindOnChargeDay,
                      onChanged: (v) => onChanged(r.copyWith(remindOnChargeDay: v)),
                    ),
                    _SwitchRow(
                      icon: LucideIcons.hourglass,
                      label: 'Cierre de la ventana de cancelación',
                      value: r.remindCancellationDeadline,
                      onChanged: (v) => onChanged(r.copyWith(remindCancellationDeadline: v)),
                    ),
                    if (r.remindCancellationDeadline)
                      _StepperRow(
                        icon: LucideIcons.timer,
                        label: 'Avisar del cierre',
                        value: r.deadlineLeadDays,
                        min: 0,
                        max: 7,
                        format: (v) => v == 0 ? 'Ese día' : '${Fmt.days(v)} antes',
                        onChanged: (v) => onChanged(r.copyWith(deadlineLeadDays: v)),
                      ),
                    PropertyRow(
                      icon: LucideIcons.clock,
                      label: 'Hora',
                      onTap: () => _pickTime(context),
                      value: Text(Fmt.time(r.hour, r.minute), style: AppType.amount),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Avisos adicionales (días antes)', style: AppType.section),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final d in _presetOffsets)
                            _OffsetChip(
                              days: d,
                              selected: r.customOffsets.contains(d),
                              onTap: () {
                                final next = {...r.customOffsets};
                                next.contains(d) ? next.remove(d) : next.add(d);
                                onChanged(r.copyWith(customOffsets: next));
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _Preview(rule: r),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Vista previa concreta: convierte la regla abstracta en días reales.
class _Preview extends StatelessWidget {
  const _Preview({required this.rule});
  final NotificationRule rule;

  @override
  Widget build(BuildContext context) {
    final offsets = rule.chargeOffsets;
    final text = offsets.isEmpty
        ? 'No recibirás avisos antes del cobro.'
        : () {
            final before = offsets.where((d) => d > 0).toList();
            final parts = <String>[
              if (before.isNotEmpty)
                '${before.length == 1 ? 'el' : 'los'} ${_joinEs(before.map((d) => '$d').toList())} '
                    '${before.length == 1 && before.first == 1 ? 'día' : 'días'} antes',
              if (offsets.contains(0)) 'el mismo día',
            ];
            return 'Recibirás ${offsets.length == 1 ? '1 aviso' : '${offsets.length} avisos'}: '
                '${_joinEs(parts)}, a las ${Fmt.time(rule.hour, rule.minute)}.';
          }();
    return NotionCallout(emoji: '🔔', child: Text(text, style: AppType.body));
  }

  static String _joinEs(List<String> items) {
    if (items.length <= 1) return items.join();
    return '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}';
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.icon, required this.label, required this.value, required this.onChanged});

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!value);
        },
        scale: 0.99,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppColors.inkTertiary),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: AppType.body)),
              Switch.adaptive(value: value, onChanged: onChanged),
            ],
          ),
        ),
      );
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    this.caption,
  });

  final IconData icon;
  final String label;
  final String? caption;
  final int value;
  final int min;
  final int max;
  final String Function(int) format;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData i, int? next, String semantic) => Pressable(
          onTap: next == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onChanged(next);
                },
          scale: 0.88,
          semanticLabel: semantic,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(i, size: 14, color: next == null ? AppColors.border : AppColors.ink),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.inkTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppType.body),
                if (caption != null) Text(caption!, style: AppType.caption),
              ],
            ),
          ),
          button(LucideIcons.minus, value > min ? value - 1 : null, 'Menos'),
          SizedBox(
            width: 104,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 120),
              child: Text(
                format(value),
                key: ValueKey(value),
                textAlign: TextAlign.center,
                style: AppType.amount.copyWith(fontSize: 14),
              ),
            ),
          ),
          button(LucideIcons.plus, value < max ? value + 1 : null, 'Más'),
        ],
      ),
    );
  }
}

class _OffsetChip extends StatelessWidget {
  const _OffsetChip({required this.days, required this.selected, required this.onTap});
  final int days;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        haptic: true,
        highlight: false,
        scale: 0.94,
        semanticLabel: '${Fmt.days(days)} antes${selected ? ', activado' : ''}',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? AppColors.ink : AppColors.border),
          ),
          child: Text(
            Fmt.days(days),
            style: AppType.caption.copyWith(
              color: selected ? AppColors.onAccent : AppColors.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
}

/// Resultado de la hoja de recordatorios de una suscripción.
class RuleSheetResult {
  const RuleSheetResult.global() : useGlobal = true, rule = null;
  const RuleSheetResult.custom(NotificationRule this.rule) : useGlobal = false;
  final bool useGlobal;
  final NotificationRule? rule;
}

/// Hoja inferior: recordatorios propios de una suscripción o los generales.
class SubscriptionRuleSheet extends StatefulWidget {
  const SubscriptionRuleSheet({super.key, required this.subscription, required this.globalRule});

  final Subscription subscription;
  final NotificationRule? globalRule;

  @override
  State<SubscriptionRuleSheet> createState() => _SubscriptionRuleSheetState();
}

class _SubscriptionRuleSheetState extends State<SubscriptionRuleSheet> {
  late bool _useGlobal = widget.subscription.notificationRule == null;
  late NotificationRule _rule =
      widget.subscription.notificationRule ?? widget.globalRule ?? NotificationRule.defaults;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(12, 0, 12, MediaQuery.paddingOf(context).bottom + 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text('Recordatorios de ${widget.subscription.name}', style: AppType.title),
                ),
                OutlineAction(
                  label: 'Guardar',
                  filled: true,
                  onTap: () => Navigator.pop(
                    context,
                    _useGlobal ? const RuleSheetResult.global() : RuleSheetResult.custom(_rule),
                  ),
                ),
              ],
            ),
          ),
          _SwitchRow(
            icon: LucideIcons.layers,
            label: 'Usar ajustes generales',
            value: _useGlobal,
            onChanged: (v) => setState(() => _useGlobal = v),
          ),
          const Divider(),
          AnimatedCrossFade(
            duration: AppMotion.medium,
            sizeCurve: AppMotion.ease,
            crossFadeState: _useGlobal ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                describeRule(widget.globalRule ?? NotificationRule.defaults),
                style: AppType.body.copyWith(color: AppColors.inkSecondary),
              ),
            ),
            secondChild: NotificationRuleEditor(
              rule: _rule,
              onChanged: (r) => setState(() => _rule = r),
            ),
          ),
        ],
      ),
    );
  }
}
