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
import '../../../../core/widgets/form_controls.dart';
import '../../../../core/widgets/line_icons.dart';
import '../../../../core/widgets/segmented_control.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../subscriptions/presentation/widgets/subscription_editor_sheet.dart';
import '../../data/logo_picker.dart';
import '../../domain/entities/merchant.dart';
import '../merchant_providers.dart';
import '../widgets/merchant_avatar.dart';

class CreateMerchantScreen extends ConsumerStatefulWidget {
  const CreateMerchantScreen({super.key, this.initialName = ''});
  final String initialName;

  @override
  ConsumerState<CreateMerchantScreen> createState() => _CreateMerchantScreenState();
}

enum _LogoMode { image, emoji, icon }

class _CreateMerchantScreenState extends ConsumerState<CreateMerchantScreen> {
  late final _name = TextEditingController(text: widget.initialName);
  final _price = TextEditingController();
  final _emojiInput = TextEditingController();

  _LogoMode _mode = _LogoMode.image;
  MerchantLogo _logo = const MerchantLogo.monogram();
  bool _picking = false;
  String? _pickError;
  SpendCategory _category = SpendCategory.other;
  CycleUnit _unit = CycleUnit.month;
  int _every = 1;
  String _currency = 'USD';
  int? _windowDays;

  static const _emojis = [
    '📱',
    '📺',
    '🎬',
    '🎧',
    '🎮',
    '☁️',
    '💻',
    '🤖',
    '📰',
    '📚',
    '🏋️',
    '🧘',
    '🎓',
    '🛒',
    '📦',
    '🚗',
    '🍔',
    '🏠',
    '⚡',
    '💡',
    '💳',
    '🏦',
    '🐶',
    '✈️',
  ];

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _emojiInput.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  Future<void> _pickImage(LogoSource source) async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _pickError = null;
    });
    try {
      final logo = await LogoPicker.pick(source);
      if (!mounted || logo == null) return;
      HapticFeedback.lightImpact();
      setState(() => _logo = logo);
    } catch (_) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _pickError = 'No se pudo leer esa imagen. Prueba con PNG o JPG.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (!_valid) return;
    final amount = double.tryParse(_price.text.replaceAll(',', '.'));
    final merchant = Merchant(
      id: 'custom.${const Uuid().v4()}',
      name: _name.text.trim(),
      category: _category,
      logo: _logo,
      isCustom: true,
      billing: BillingDefaults(
        cycle: BillingCycle(unit: _unit, every: _every),
        price: amount == null ? null : Money.fromMajor(amount, _currency),
        cancellationWindowDays: _windowDays,
      ),
    );
    await ref.read(merchantRepositoryProvider).saveCustom(merchant);
    if (!mounted) return;
    // Continúa directamente al formulario de la suscripción con este comercio.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => SubscriptionEditorSheet(merchant: merchant)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comercio personalizado'),
        leading: IconButton(
          tooltip: 'Atrás',
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AnimatedOpacity(
              opacity: _valid ? 1 : 0.4,
              duration: AppMotion.short,
              child: PillButton(label: 'Continuar', filled: true, onTap: _valid ? _save : null),
            ),
          ),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.paddingOf(context).bottom + 32),
        children: [
          // Vista previa en vivo: así se verá en el dashboard.
          Row(
            children: [
              AnimatedSwitcher(
                duration: AppMotion.short,
                transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                child: MerchantAvatar(
                  key: ValueKey(_logo),
                  logo: _logo,
                  name: name.isEmpty ? '?' : name,
                  size: 56,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: widget.initialName.isEmpty,
                  textCapitalization: TextCapitalization.words,
                  style: AppType.title,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Nombre del comercio',
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
          Text('Logo', style: AppType.footnote.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedControl<_LogoMode>(
            values: const [_LogoMode.image, _LogoMode.emoji, _LogoMode.icon],
            selected: _mode,
            label: (m) => switch (m) {
              _LogoMode.image => 'Imagen',
              _LogoMode.emoji => 'Emoji',
              _LogoMode.icon => 'Icono',
            },
            onChanged: (m) => setState(() => _mode = m),
          ),
          const SizedBox(height: 12),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.ease,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: AppMotion.short,
              switchInCurve: AppMotion.ease,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              layoutBuilder: (current, previous) =>
                  Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
              child: switch (_mode) {
                _LogoMode.image => _imagePicker(),
                _LogoMode.emoji => _emojiPicker(),
                _LogoMode.icon => _iconPicker(),
              },
            ),
          ),
          const SizedBox(height: 24),
          const FieldLabel('Categoría'),
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
          const SizedBox(height: 24),
          Text('Reglas de cobro por defecto', style: AppType.footnote.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Se precargan al registrar una suscripción de este comercio.', style: AppType.caption),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Cada', style: AppType.body),
              const SizedBox(width: 10),
              CountStepper(value: _every, onChanged: (v) => setState(() => _every = v)),
              const SizedBox(width: 10),
              Expanded(
                child: SegmentedControl<CycleUnit>(
                  values: const [CycleUnit.week, CycleUnit.month, CycleUnit.year],
                  selected: _unit == CycleUnit.day ? CycleUnit.week : _unit,
                  label: (u) => switch (u) {
                    CycleUnit.week => 'Semana',
                    CycleUnit.month => 'Mes',
                    _ => 'Año',
                  },
                  onChanged: (u) => setState(() => _unit = u),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: 'Precio habitual (opcional)'),
                ),
              ),
              const SizedBox(width: 8),
              CurrencyMenu(value: _currency, onChanged: (c) => setState(() => _currency = c)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            keyboardType: TextInputType.number,
            onChanged: (v) => _windowDays = int.tryParse(v),
            decoration: const InputDecoration(
              hintText: 'Días para cancelar tras el cobro (opcional)',
              prefixIcon: Icon(LucideIcons.hourglass, size: 16, color: AppColors.inkTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePicker() => Column(
    key: const ValueKey('image'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: _SourceButton(
              icon: LucideIcons.images,
              label: 'Fotos',
              busy: _picking,
              onTap: () => _pickImage(LogoSource.photos),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SourceButton(
              icon: LucideIcons.folderOpen,
              label: 'Archivos',
              busy: _picking,
              onTap: () => _pickImage(LogoSource.files),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      AnimatedSwitcher(
        duration: AppMotion.short,
        child: Text(
          _pickError ?? 'PNG, JPG, WebP o ICO. Se recorta en cuadrado y se guarda en la app.',
          key: ValueKey(_pickError),
          style: AppType.caption.copyWith(color: _pickError == null ? null : AppColors.danger),
        ),
      ),
    ],
  );

  Widget _emojiPicker() => Column(
    key: const ValueKey('emoji'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final e in _emojis)
            _LogoCell(
              selected: _logo == MerchantLogo.emoji(e),
              onTap: () => setState(() => _logo = MerchantLogo.emoji(e)),
              child: Text(e, style: const TextStyle(fontSize: 20)),
            ),
        ],
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _emojiInput,
        decoration: const InputDecoration(hintText: 'O escribe cualquier emoji'),
        onChanged: (v) {
          final c = v.characters;
          if (c.isEmpty) return;
          // Solo el último grafema: un emoji compuesto cuenta como uno.
          setState(() => _logo = MerchantLogo.emoji(c.last));
        },
      ),
    ],
  );

  Widget _iconPicker() => Wrap(
    key: const ValueKey('icon'),
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final e in kLineIcons.entries)
        _LogoCell(
          selected: _logo == MerchantLogo.icon(e.key),
          onTap: () => setState(() => _logo = MerchantLogo.icon(e.key)),
          child: Icon(e.value, size: 18, color: AppColors.ink),
        ),
    ],
  );
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({required this.icon, required this.label, required this.busy, required this.onTap});
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: busy ? null : onTap,
    haptic: true,
    highlight: false,
    scale: 0.96,
    borderRadius: BorderRadius.circular(8),
    child: AnimatedOpacity(
      duration: AppMotion.short,
      opacity: busy ? 0.5 : 1,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppColors.ink),
            const SizedBox(width: 8),
            Text(label, style: AppType.body.copyWith(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    ),
  );
}

class _LogoCell extends StatelessWidget {
  const _LogoCell({required this.selected, required this.onTap, required this.child});
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    haptic: true,
    highlight: false,
    scale: 0.9,
    child: SelectionPop(
      active: selected,
      amount: 0.12,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.callout : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppColors.ink : AppColors.border, width: selected ? 1.5 : 1),
        ),
        child: child,
      ),
    ),
  );
}
