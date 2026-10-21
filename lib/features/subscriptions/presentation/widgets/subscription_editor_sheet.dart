import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/di/core_providers.dart';
import '../../../../core/domain/billing_cycle.dart';
import '../../../../core/domain/money.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/amount_keypad.dart';
import '../../../../core/widgets/form_controls.dart';
import '../../../../core/widgets/list_row.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../../core/widgets/segmented_control.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/presentation/merchant_providers.dart';
import '../../../merchants/presentation/screens/catalog_screen.dart';
import '../../../merchants/presentation/widgets/merchant_avatar.dart';
import '../../../notifications/domain/notification_rule.dart';
import '../../../notifications/presentation/notification_providers.dart';
import '../../../notifications/presentation/widgets/notification_rule_editor.dart';
import '../../../wallet/presentation/wallet_providers.dart';
import '../../domain/charge_pattern.dart';
import '../../domain/entities/subscription.dart';
import '../subscription_providers.dart';

/// Abre la hoja de alta o edición de una suscripción.
Future<void> showSubscriptionEditor(BuildContext context, {Merchant? merchant, Subscription? editing}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => SubscriptionEditorSheet(merchant: merchant, editing: editing),
    ));

/// Alta y edición de una suscripción: logo y nombre grandes, el importe muy
/// grande con el teclado propio, y filas "Frecuencia" y "Se renueva el".
class SubscriptionEditorSheet extends ConsumerStatefulWidget {
  const SubscriptionEditorSheet({super.key, this.merchant, this.editing});

  final Merchant? merchant;
  final Subscription? editing;

  @override
  ConsumerState<SubscriptionEditorSheet> createState() => _SubscriptionEditorSheetState();
}

class _SubscriptionEditorSheetState extends ConsumerState<SubscriptionEditorSheet> {
  late final Subscription? _e = widget.editing;
  late Merchant? _merchant = widget.merchant;
  late final BillingDefaults _defaults = widget.merchant?.billing ?? const BillingDefaults();

  late final _name = TextEditingController(text: _e?.name ?? widget.merchant?.name ?? '');
  late final _notes = TextEditingController(text: _e?.notes ?? '');
  late final _payLabel = TextEditingController(text: _e?.paymentMethod.label ?? '');
  late final _last4 = TextEditingController(text: _e?.paymentMethod.last4 ?? '');
  late final AmountInput _amount = AmountInput()..setMinor(_e?.price.minor ?? _defaults.price?.minor ?? 0);

  String? _currency;
  late CycleUnit _unit = _e?.cycle.unit ?? _defaults.cycle.unit;
  late int _every = _e?.cycle.every ?? _defaults.cycle.every;
  DateTime? _date;
  late SubscriptionStatus _status = _e?.status ?? SubscriptionStatus.active;
  late SpendCategory _category = _e?.category ?? widget.merchant?.category ?? SpendCategory.other;
  late PaymentKind _payKind = _e?.paymentMethod.kind ?? PaymentKind.card;
  late bool _hasWindow = (_e?.cancellationWindow ?? _defaults.cancellationWindowDays) != null;
  late int _windowDays = _e?.cancellationWindow?.days ?? _defaults.cancellationWindowDays ?? 7;
  late CancellationPolicy _policy = _e?.cancellationWindow?.policy ?? CancellationPolicy.afterCharge;
  late NotificationRule? _rule = _e?.notificationRule;

  /// El teclado se abre solo si aún no hay importe.
  late bool _keypad = _amount.minor == 0;
  bool _more = false;
  bool _dateTouched = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_name, _notes, _payLabel, _last4]) {
      c.dispose();
    }
    _amount.dispose();
    super.dispose();
  }

  DateTime _defaultDate(DateTime now) =>
      _e?.nextCharge(now) ?? _e?.firstChargeDate ?? DateTime(now.year, now.month, now.day + 1);

  Future<void> _pickDate(DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Se renueva el',
    );
    if (picked != null) {
      HapticFeedback.selectionClick();
      setState(() {
        _date = picked;
        _dateTouched = true;
      });
    }
  }

  Future<void> _pickMerchant() async {
    final m = await Navigator.of(context).push<Merchant>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const CatalogScreen(pickOnly: true),
    ));
    if (m == null) return;
    setState(() {
      if (_name.text.trim().isEmpty || _name.text == _merchant?.name) _name.text = m.name;
      _merchant = m;
      _category = m.category;
    });
  }

  Future<void> _pickFrequency() => showModalBottomSheet<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setSheet) {
            void update(VoidCallback f) {
              setState(f);
              setSheet(() {});
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Frecuencia', style: AppType.title2),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('Cada', style: AppType.body),
                        const SizedBox(width: 12),
                        CountStepper(value: _every, onChanged: (v) => update(() => _every = v)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SegmentedControl<CycleUnit>(
                      values: const [CycleUnit.week, CycleUnit.month, CycleUnit.year],
                      selected: _unit == CycleUnit.day ? CycleUnit.week : _unit,
                      label: (u) => switch (u) {
                        CycleUnit.week => _every == 1 ? 'Semana' : 'Semanas',
                        CycleUnit.month => _every == 1 ? 'Mes' : 'Meses',
                        _ => _every == 1 ? 'Año' : 'Años',
                      },
                      onChanged: (u) => update(() => _unit = u),
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(label: 'Listo', onTap: () => Navigator.pop(context)),
                  ],
                ),
              ),
            );
          },
        ),
      );

  Future<void> _pickReminder() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setSheet) {
            final global = ref.read(globalRuleProvider).value ?? NotificationRule.defaults;
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recordatorio', style: AppType.title2),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Usar los de Ajustes', style: AppType.body),
                      value: _rule == null,
                      onChanged: (v) {
                        setState(() => _rule = v ? null : global);
                        setSheet(() {});
                      },
                    ),
                    AnimatedSize(
                      duration: AppMotion.medium,
                      curve: AppMotion.ease,
                      child: _rule == null
                          ? const SizedBox(width: double.infinity)
                          : NotificationRuleEditor(
                              rule: _rule!,
                              onChanged: (r) {
                                setState(() => _rule = r);
                                setSheet(() {});
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Eliminar ${_e!.name}?'),
        content: const Text('Dejarás de recibir sus avisos. Los gastos ya registrados se conservan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    HapticFeedback.heavyImpact();
    await ref.read(subscriptionActionsProvider).delete(_e!.id);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _save(String currency, DateTime date) async {
    final name = _name.text.trim();
    if (_amount.minor <= 0 || name.isEmpty) {
      HapticFeedback.heavyImpact();
      setState(() => _keypad = _amount.minor <= 0);
      return;
    }
    setState(() => _saving = true);
    final now = ref.read(nowProvider);

    // La fecha elegida se convierte en el ancla del calendario de cobros,
    // salvo al editar sin tocar fecha ni ciclo: se conserva el ancla original.
    final cycle = BillingCycle(unit: _unit, every: _every);
    final keepAnchor = _e != null && !_dateTouched && _e.cycle == cycle;
    final s = Subscription(
      id: _e?.id ?? const Uuid().v4(),
      merchantId: _merchant?.id ?? _e!.merchantId,
      name: name,
      price: Money(_amount.minor, currency),
      cycle: cycle,
      firstChargeDate: keepAnchor ? _e.firstChargeDate : date,
      category: _category,
      paymentMethod: PaymentMethod(
        kind: _payKind,
        label: _payLabel.text.trim(),
        last4: _last4.text.trim().isEmpty ? null : _last4.text.trim(),
      ),
      status: _status,
      statusChangedAt: _e?.status != _status ? now : _e?.statusChangedAt,
      cancellationWindow: _hasWindow ? CancellationWindow(days: _windowDays, policy: _policy) : null,
      notificationRule: _rule,
      notes: _notes.text.trim(),
      createdAt: _e?.createdAt ?? now,
      // El historial de cobros se conserva al editar; el patrón se reajusta al
      // día de la nueva fecha si el usuario la cambió.
      chargeHistory: _e?.chargeHistory ?? const [],
      chargePattern: keepAnchor
          ? _e.chargePattern
          : (_dateTouched ? _e?.chargePattern?.withDayOf(date) : null) ?? ChargePattern.sameDay(date.day),
      cancelQuestionCharge: _e?.cancelQuestionCharge,
    );

    await ref.read(subscriptionActionsProvider).save(s);
    HapticFeedback.mediumImpact();
    // Momento oportuno para pedir permiso: acaba de crear algo que avisar.
    if (_e == null) await ref.read(requestNotificationPermissionProvider)();
    if (!mounted) return;
    final nav = Navigator.of(context);
    // Alta: cierra todo el flujo (catálogo → hoja). Edición: vuelve al detalle.
    _e == null ? nav.popUntil((r) => r.isFirst) : nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowProvider);
    final currency =
        _currency ?? _e?.price.currency ?? _defaults.price?.currency ?? ref.watch(walletSettingsProvider).value?.currency ?? 'PEN';
    final date = _date ?? _defaultDate(now);
    final logo = _merchant?.logo ?? ref.watch(merchantByIdProvider(_e?.merchantId))?.logo ?? const MerchantLogo.monogram();

    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return SheetScaffold(
      title: _e == null ? 'Nueva suscripción' : 'Editar suscripción',
      trailing: _e == null
          ? null
          : CircleIconButton(icon: LucideIcons.trash2, label: 'Eliminar', onTap: _delete),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.ease,
            alignment: Alignment.bottomCenter,
            child: _keypad ? AmountKeypad(input: _amount) : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 8),
          PrimaryButton(label: 'Guardar', loading: _saving, onTap: () => _save(currency, date)),
        ],
      ),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          Center(
            child: Entrance(
              scale: 0.6,
              offset: Offset.zero,
              curve: Curves.easeOutBack,
              duration: const Duration(milliseconds: 600),
              child: Pressable(
                onTap: _pickMerchant,
                highlight: false,
                scale: 0.94,
                borderRadius: BorderRadius.circular(48),
                semanticLabel: 'Cambiar de negocio',
                child: MerchantAvatar(
                  logo: logo,
                  name: _name.text,
                  size: 96,
                  heroTag: _e == null ? null : 'logo-${_e.id}',
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          e(TextField(
            controller: _name,
            textAlign: TextAlign.center,
            style: AppType.title1,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Nombre',
              filled: false,
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          )),
          const SizedBox(height: 6),
          e(Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Pressable(
                  onTap: () => setState(() => _keypad = !_keypad),
                  highlight: false,
                  borderRadius: BorderRadius.circular(16),
                  semanticLabel: 'Importe',
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _amount.display(currency),
                      style: AppType.amountHero.copyWith(
                        fontSize: 46,
                        color: _amount.isEmpty ? AppColors.inkTertiary : AppColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CurrencyMenu(value: currency, onChanged: (c) => setState(() => _currency = c)),
            ],
          )),
          const SizedBox(height: 22),
          e(ListRow(label: 'Frecuencia', value: Fmt.cycle(BillingCycle(unit: _unit, every: _every)), onTap: _pickFrequency)),
          const SizedBox(height: 8),
          e(ListRow(
            label: 'Se renueva el',
            value: _capitalize(Fmt.dateLong(date)),
            valueColor: AppColors.ink,
            onTap: () => _pickDate(date),
          )),
          const SizedBox(height: 8),
          e(ListRow(
            label: 'Recordatorio',
            value: _rule == null ? 'Como en Ajustes' : 'Personalizado',
            onTap: _pickReminder,
          )),
          const SizedBox(height: 8),
          e(SurfaceCard(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: TextField(
              controller: _notes,
              minLines: 1,
              maxLines: 4,
              style: AppType.body,
              decoration: const InputDecoration(
                hintText: 'Añadir una nota',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          )),
          const SizedBox(height: 14),
          e(Center(
            child: Pressable(
              onTap: () => setState(() => _more = !_more),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _more ? 'Menos opciones' : 'Más opciones',
                      style: AppType.subhead.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _more ? 0.5 : 0,
                      duration: AppMotion.medium,
                      child: const Icon(LucideIcons.chevronDown, size: 16, color: AppColors.accent),
                    ),
                  ],
                ),
              ),
            ),
          )),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.ease,
            alignment: Alignment.topCenter,
            child: _more ? _moreOptions() : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _moreOptions() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const FieldLabel('Estado'),
          SegmentedControl<SubscriptionStatus>(
            values: const [SubscriptionStatus.active, SubscriptionStatus.trial, SubscriptionStatus.paused],
            selected: _status == SubscriptionStatus.cancelled ? SubscriptionStatus.paused : _status,
            label: (s) => switch (s) {
              SubscriptionStatus.trial => 'Prueba',
              SubscriptionStatus.paused => 'Pausada',
              _ => 'Activa',
            },
            onChanged: (s) => setState(() => _status = s),
          ),
          const SizedBox(height: 18),
          const FieldLabel('Método de pago'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in PaymentKind.values)
                ChoiceTag(label: k.label, selected: k == _payKind, onTap: () => setState(() => _payKind = k)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _payLabel,
                  decoration: const InputDecoration(hintText: 'Banco o alias (opcional)'),
                ),
              ),
              if (_payKind == PaymentKind.card) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _last4,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(hintText: 'Últimos 4', counterText: ''),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          const FieldLabel('Categoría'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in SpendCategory.values)
                ChoiceTag(label: c.label, selected: c == _category, onTap: () => setState(() => _category = c)),
            ],
          ),
          const SizedBox(height: 18),
          SurfaceCard(
            radius: 18,
            padding: const EdgeInsets.fromLTRB(18, 6, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Plazo para cancelar', style: AppType.body)),
                    Switch.adaptive(value: _hasWindow, onChanged: (v) => setState(() => _hasWindow = v)),
                  ],
                ),
                AnimatedSize(
                  duration: AppMotion.medium,
                  curve: AppMotion.ease,
                  alignment: Alignment.topCenter,
                  child: !_hasWindow
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(0, 4, 8, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SegmentedControl<CancellationPolicy>(
                                values: CancellationPolicy.values,
                                selected: _policy,
                                label: (p) =>
                                    p == CancellationPolicy.afterCharge ? 'Después del cobro' : 'Antes del cobro',
                                onChanged: (p) => setState(() => _policy = p),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  CountStepper(
                                    value: _windowDays,
                                    min: 0,
                                    max: 90,
                                    onChanged: (v) => setState(() => _windowDays = v),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _policy == CancellationPolicy.afterCharge
                                          ? 'días para cancelar y pedir reembolso tras el cobro'
                                          : 'días de antelación que exige el comercio',
                                      style: AppType.footnote,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      );

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
