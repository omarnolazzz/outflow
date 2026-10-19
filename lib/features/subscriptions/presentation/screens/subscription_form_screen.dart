import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/domain/billing_cycle.dart';
import '../../../../core/domain/money.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/form_controls.dart';
import '../../../../core/widgets/notion_widgets.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../core/widgets/segmented.dart';
import '../../../merchants/domain/entities/merchant.dart';
import '../../../merchants/presentation/widgets/merchant_avatar.dart';
import '../../../notifications/presentation/notification_providers.dart';
import '../../domain/charge_pattern.dart';
import '../../domain/entities/subscription.dart';
import '../subscription_providers.dart';

/// Alta y edición de una suscripción. Al crear, se precarga con las reglas
/// por defecto del comercio elegido.
class SubscriptionFormScreen extends ConsumerStatefulWidget {
  const SubscriptionFormScreen.create({super.key, required Merchant this.merchant}) : existing = null;

  const SubscriptionFormScreen.edit({super.key, required Subscription subscription, this.merchant})
    : existing = subscription;

  final Merchant? merchant;
  final Subscription? existing;

  @override
  ConsumerState<SubscriptionFormScreen> createState() => _SubscriptionFormScreenState();
}

class _SubscriptionFormScreenState extends ConsumerState<SubscriptionFormScreen> {
  late final Subscription? _e = widget.existing;
  late final BillingDefaults _defaults = widget.merchant?.billing ?? const BillingDefaults();

  late final _name = TextEditingController(text: _e?.name ?? widget.merchant?.name ?? '');
  late final _amount = TextEditingController(
    text: _e != null ? _e.price.major.toStringAsFixed(2) : _defaults.price?.major.toStringAsFixed(2) ?? '',
  );
  late final _payLabel = TextEditingController(text: _e?.paymentMethod.label ?? '');
  late final _last4 = TextEditingController(text: _e?.paymentMethod.last4 ?? '');
  late final _notes = TextEditingController(text: _e?.notes ?? '');

  late String _currency = _e?.price.currency ?? _defaults.price?.currency ?? 'USD';
  late CycleUnit _unit = _e?.cycle.unit ?? _defaults.cycle.unit;
  late int _every = _e?.cycle.every ?? _defaults.cycle.every;
  late DateTime _date = _e?.nextCharge(DateTime.now()) ?? _e?.firstChargeDate ?? _tomorrow();
  late SubscriptionStatus _status = _e?.status ?? SubscriptionStatus.active;
  late SpendCategory _category = _e?.category ?? widget.merchant?.category ?? SpendCategory.other;
  late PaymentKind _payKind = _e?.paymentMethod.kind ?? PaymentKind.card;
  late bool _hasWindow = (_e?.cancellationWindow ?? _defaults.cancellationWindowDays) != null;
  late int _windowDays = _e?.cancellationWindow?.days ?? _defaults.cancellationWindowDays ?? 7;
  late CancellationPolicy _policy = _e?.cancellationWindow?.policy ?? CancellationPolicy.afterCharge;

  bool _triedSave = false;
  bool _dateTouched = false;

  static DateTime _tomorrow() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + 1);
  }

  double? get _parsedAmount {
    final v = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
    return v != null && v >= 0 ? v : null;
  }

  String? get _amountError => _triedSave && _parsedAmount == null ? 'Escribe un monto válido' : null;
  String? get _nameError => _triedSave && _name.text.trim().isEmpty ? 'Ponle un nombre' : null;

  @override
  void dispose() {
    for (final c in [_name, _amount, _payLabel, _last4, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Fecha del próximo cobro',
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        _dateTouched = true;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _triedSave = true);
    final amount = _parsedAmount;
    if (amount == null || _name.text.trim().isEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }

    // La fecha elegida se convierte en el ancla del calendario de cobros,
    // salvo al editar sin tocar fecha ni ciclo: se conserva el ancla original.
    final keepAnchor = _e != null && !_dateTouched && _e.cycle == BillingCycle(unit: _unit, every: _every);
    final s = Subscription(
      id: _e?.id ?? const Uuid().v4(),
      merchantId: _e?.merchantId ?? widget.merchant!.id,
      name: _name.text.trim(),
      price: Money.fromMajor(amount, _currency),
      cycle: BillingCycle(unit: _unit, every: _every),
      firstChargeDate: keepAnchor ? _e.firstChargeDate : _date,
      category: _category,
      paymentMethod: PaymentMethod(
        kind: _payKind,
        label: _payLabel.text.trim(),
        last4: _last4.text.trim().isEmpty ? null : _last4.text.trim(),
      ),
      status: _status,
      statusChangedAt: _e?.status != _status ? DateTime.now() : _e?.statusChangedAt,
      cancellationWindow: _hasWindow ? CancellationWindow(days: _windowDays, policy: _policy) : null,
      notificationRule: _e?.notificationRule,
      notes: _notes.text.trim(),
      createdAt: _e?.createdAt ?? DateTime.now(),
      // El historial de cobros se conserva al editar; el patrón se reajusta al
      // día de la nueva fecha si el usuario la cambió.
      chargeHistory: _e?.chargeHistory ?? const [],
      chargePattern: keepAnchor
          ? _e.chargePattern
          : (_dateTouched ? _e?.chargePattern?.withDayOf(_date) : null) ?? ChargePattern.sameDay(_date.day),
    );

    await ref.read(subscriptionActionsProvider).save(s);
    HapticFeedback.mediumImpact();
    if (_e == null) {
      // Momento oportuno para pedir permiso: acaba de crear algo que avisar.
      await ref.read(notificationServiceProvider).requestPermission();
    }
    if (!mounted) return;
    final nav = Navigator.of(context);
    // Alta: cierra todo el flujo (catálogo → formulario) y vuelve al dashboard.
    // Edición: vuelve al detalle, que ya refleja los cambios.
    _e == null ? nav.popUntil((r) => r.isFirst) : nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final logo = widget.merchant?.logo ?? const MerchantLogo.monogram();

    // Los bloques del formulario entran de arriba abajo, uno tras otro.
    var order = 0;
    Widget e(Widget child) => Entrance(index: ++order, child: child);

    return Scaffold(
      appBar: AppBar(
        title: Text(_e == null ? 'Detalles' : 'Editar'),
        leading: IconButton(
          tooltip: _e == null ? 'Atrás' : 'Cerrar',
          icon: Icon(_e == null ? LucideIcons.chevronLeft : LucideIcons.x),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlineAction(label: 'Guardar', filled: true, onTap: _save),
          ),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.paddingOf(context).bottom + 40),
        children: [
          Row(
            children: [
              Entrance(
                scale: 0.6,
                offset: Offset.zero,
                curve: Curves.easeOutBack,
                child: MerchantAvatar(logo: logo, name: _name.text, size: 48),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  style: AppType.title,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Nombre',
                    errorText: _nameError,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          e(const FieldLabel('Monto')),
          e(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    autofocus: _e == null && _amount.text.isEmpty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    style: AppType.amount.copyWith(fontSize: 17),
                    // Validación en línea, no solo al guardar.
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(hintText: '0.00', errorText: _amountError),
                  ),
                ),
                const SizedBox(width: 8),
                CurrencyMenu(value: _currency, onChanged: (c) => setState(() => _currency = c)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          e(const FieldLabel('Se cobra')),
          e(
            Row(
              children: [
                Text('Cada', style: AppType.body),
                const SizedBox(width: 10),
                CountStepper(value: _every, onChanged: (v) => setState(() => _every = v)),
                const SizedBox(width: 10),
                Expanded(
                  child: NotionSegmented<CycleUnit>(
                    value: _unit,
                    options: const {CycleUnit.week: 'Semana', CycleUnit.month: 'Mes', CycleUnit.year: 'Año'},
                    onChanged: (u) => setState(() => _unit = u),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          e(
            Pressable(
              onTap: _pickDate,
              child: NotionBlock(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                color: AppColors.surfaceMuted,
                child: Row(
                  children: [
                    const Icon(LucideIcons.calendar, size: 16, color: AppColors.inkTertiary),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Próximo cobro', style: AppType.body)),
                    // La fecha nueva entra con un fundido al elegirla.
                    AnimatedSwitcher(
                      duration: AppMotion.short,
                      child: Text(Fmt.dateShort(_date), key: ValueKey(_date), style: AppType.bodyStrong),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          e(const FieldLabel('Estado')),
          e(
            NotionSegmented<SubscriptionStatus>(
              value: _status,
              options: const {
                SubscriptionStatus.active: 'Activa',
                SubscriptionStatus.trial: 'Prueba',
                SubscriptionStatus.paused: 'Pausada',
              },
              onChanged: (s) => setState(() => _status = s),
            ),
          ),
          const SizedBox(height: 20),
          e(const FieldLabel('Método de pago')),
          e(
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in PaymentKind.values)
                  ChoiceTag(
                    label: k.label,
                    selected: k == _payKind,
                    onTap: () => setState(() => _payKind = k),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // El campo "Últimos 4" aparece/desaparece deslizándose.
          e(
            AnimatedSize(
              duration: AppMotion.medium,
              curve: AppMotion.ease,
              child: Row(
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
            ),
          ),
          const SizedBox(height: 20),
          e(const FieldLabel('Categoría')),
          e(
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in SpendCategory.values)
                  ChoiceTag(
                    label: c.label,
                    selected: c == _category,
                    onTap: () => setState(() => _category = c),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          e(
            NotionBlock(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.hourglass, size: 16, color: AppColors.inkTertiary),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Ventana de cancelación', style: AppType.bodyStrong)),
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
                                NotionSegmented<CancellationPolicy>(
                                  value: _policy,
                                  options: const {
                                    CancellationPolicy.afterCharge: 'Después del cobro',
                                    CancellationPolicy.beforeCharge: 'Antes del cobro',
                                  },
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
                                        style: AppType.caption,
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
          ),
          const SizedBox(height: 20),
          e(const FieldLabel('Notas')),
          e(
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(hintText: 'Cómo cancelar, cuenta asociada…'),
            ),
          ),
        ],
      ),
    );
  }
}
