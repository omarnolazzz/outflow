import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/domain/money.dart';
import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../capture/data/capture_inbox.dart';
import '../../capture/data/capture_key.dart';
import '../../capture/data/capture_sources_repository.dart';
import '../../capture/domain/capture_link.dart';
import '../../capture/domain/parse_bank_text.dart';
import '../../capture/presentation/capture_link_handler.dart';
import '../../wallet/domain/wallet_account.dart';
import '../../wallet/presentation/wallet_providers.dart';

/// URL que abre la automatización de Atajos con el correo. "Scotiabank" se cambia
/// por el nombre del banco y "TextoCodificado" por el resultado de "Codificar URL".
String emailShortcutUrl(String key) => 'outflow://captura?clave=$key&fuente=Scotiabank&texto=TextoCodificado';

const _steps = <(IconData, String, String)>[
  (
    LucideIcons.mail,
    'Añade tu Gmail al iPhone',
    'Ajustes → Mail → Cuentas → Añadir cuenta → Google. Así Atajos puede ver los correos nuevos.',
  ),
  (
    LucideIcons.layers,
    'Crea la automatización',
    'En la app Atajos: Automatización → Nueva automatización → Correo. En "Remitente" pon el correo '
        'del aviso de tu banco (por ejemplo soporte@lemon.me para Dale, o el que usa Scotiabank). '
        'Marca "Ejecutar inmediatamente".',
  ),
  (
    LucideIcons.code,
    'Añade la acción "Codificar URL"',
    'Elige la variable "Entrada del atajo" (el texto del correo). Es necesario: sin codificar, los '
        'espacios y símbolos del correo cortan el enlace.',
  ),
  (
    LucideIcons.link,
    'Añade la acción "Abrir URL"',
    'Pega la URL de abajo con el botón Copiar. Cambia "Scotiabank" por el nombre de tu banco y '
        '"TextoCodificado" por el resultado de "Codificar URL".',
  ),
  (
    LucideIcons.circleCheck,
    'Listo',
    'Cada correo del banco se apuntará solo, como "por revisar". Outflow se abre un momento cada vez: '
        'es normal, el iPhone no deja leer correos en segundo plano.',
  ),
];

/// iPhone: captura de correos bancarios con una automatización de Atajos, y modo
/// diagnóstico para ver qué entiende la app de un texto.
class EmailCaptureGuideScreen extends ConsumerStatefulWidget {
  const EmailCaptureGuideScreen({super.key});

  @override
  ConsumerState<EmailCaptureGuideScreen> createState() => _EmailCaptureGuideScreenState();
}

class _EmailCaptureGuideScreenState extends ConsumerState<EmailCaptureGuideScreen> {
  String? _key;
  bool _probed = false;
  late Map<String, String> _sources = ref.read(captureSourcesRepositoryProvider).read();
  final _newSource = TextEditingController();
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    ref.read(captureKeyStoreProvider).key().then((k) {
      if (mounted) setState(() => _key = k);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  @override
  void dispose() {
    _newSource.dispose();
    // El texto del último correo no sobrevive a la guía. Fuera del desmontaje, para
    // no tocar un proveedor mientras se reconstruye el árbol.
    final container = _container;
    Future.microtask(() {
      try {
        container.read(lastCaptureProvider.notifier).set(null);
      } on StateError {
        // El contenedor ya se cerró con la app: no queda nada que borrar.
      }
    });
    super.dispose();
  }

  void _copy() {
    final key = _key;
    if (key == null) return;
    Clipboard.setData(ClipboardData(text: emailShortcutUrl(key)));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('URL copiada. Pégala en la acción "Abrir URL".')));
  }

  void _useSample() {
    ref.read(lastCaptureProvider.notifier).set(CaptureEvent(
          sourceKey: 'email:ejemplo',
          sourceLabel: 'Ejemplo',
          text: kCaptureSampleText,
          receivedAt: ref.read(nowProvider),
        ));
    setState(() => _probed = true);
  }

  Future<void> _addSource(List<WalletAccount> accounts) async {
    final label = _newSource.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (label.isEmpty || accounts.isEmpty) return;
    final shown = label.length > kCaptureSourceLimit ? label.substring(0, kCaptureSourceLimit) : label;
    final key = 'email:${shown.toLowerCase().trim()}';
    final account = defaultAccountOf(accounts)!;
    await ref.read(captureSourcesRepositoryProvider).assign(key, account.id);
    _newSource.clear();
    if (mounted) setState(() => _sources = ref.read(captureSourcesRepositoryProvider).read());
  }

  Future<void> _assign(String sourceKey, String accountId) async {
    await ref.read(captureSourcesRepositoryProvider).assign(sourceKey, accountId);
    if (mounted) setState(() => _sources = ref.read(captureSourcesRepositoryProvider).read());
  }

  @override
  Widget build(BuildContext context) {
    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);
    final accounts = ref.watch(activeAccountsProvider);
    final last = ref.watch(lastCaptureProvider);
    final sourceKeys = {
      for (final k in _sources.keys)
        if (k.startsWith('email:')) k,
      if (last != null && last.sourceKey.startsWith('email:')) last.sourceKey,
    }.toList()
      ..sort();

    return SheetScaffold(
      title: 'Captura por correo',
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.paddingOf(context).bottom + 32),
        children: [
          e(Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
              child: const Icon(LucideIcons.mailCheck, size: 36, color: AppColors.accent),
            ),
          )),
          const SizedBox(height: 14),
          e(Text('Apunta los correos de tu banco', textAlign: TextAlign.center, style: AppType.title1)),
          const SizedBox(height: 8),
          e(Text(
            'En iPhone, Outflow no puede leer otras apps. Pero un atajo puede mandarle el texto de cada '
            'correo del banco, y Outflow lo deja "por revisar". Se abre un momento cada vez que llega uno.',
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
                    _key == null ? '…' : emailShortcutUrl(_key!),
                    style: AppType.footnote.copyWith(color: AppColors.ink, fontFamily: 'Menlo'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Lleva una clave solo tuya: sin ella, Outflow ignora el enlace. No la compartas.',
                  style: AppType.caption,
                ),
                const SizedBox(height: 10),
                PillButton(label: 'Copiar', icon: LucideIcons.copy, onTap: _key == null ? null : _copy),
              ],
            ),
          )),
          const SizedBox(height: 16),
          e(SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cuenta de cada banco', style: AppType.headline),
                const SizedBox(height: 4),
                Text(
                  'Escribe el mismo nombre que pusiste en "fuente" (Scotiabank, Dale…). Si no eliges '
                  'cuenta, el gasto va a la principal.',
                  style: AppType.subhead,
                ),
                for (final k in sourceKeys)
                  Row(
                    key: ValueKey('source:$k'),
                    children: [
                      Expanded(child: Text(_labelOf(k, last), style: AppType.body)),
                      if (accounts.isNotEmpty)
                        Flexible(
                          child: DropdownButton<String>(
                            value: accounts.any((a) => a.id == _sources[k]) ? _sources[k] : null,
                            isExpanded: true,
                            underline: const SizedBox.shrink(),
                            hint: Text('La principal', style: AppType.subhead),
                            items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
                            onChanged: (id) {
                              if (id != null) _assign(k, id);
                            },
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('sourceName'),
                  controller: _newSource,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Nombre del banco'),
                  onSubmitted: (_) => _addSource(accounts),
                ),
                const SizedBox(height: 8),
                PillButton(label: 'Añadir fuente', icon: LucideIcons.plus, onTap: () => _addSource(accounts)),
              ],
            ),
          )),
          const SizedBox(height: 20),
          e(PrimaryButton(
            label: 'Probar',
            icon: const Icon(LucideIcons.play, size: 18, color: AppColors.onAccent),
            onTap: () => setState(() => _probed = true),
          )),
          const SizedBox(height: 8),
          e(Text(
            'Muestra el último texto que llegó con tu clave y lo que Outflow entendió de él.',
            textAlign: TextAlign.center,
            style: AppType.caption,
          )),
          const SizedBox(height: 10),
          e(PrimaryButton(label: 'Probar con un ejemplo', secondary: true, onTap: _useSample)),
          if (_probed) ...[
            const SizedBox(height: 16),
            e(_Diagnosis(event: last, currency: ref.read(walletSettingsRepositoryProvider).read().currency, now: ref.read(nowProvider))),
          ],
        ],
      ),
    );
  }

  String _labelOf(String key, CaptureEvent? last) {
    if (last != null && last.sourceKey == key) return last.sourceLabel;
    final name = key.substring('email:'.length);
    return name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
  }
}

/// El último texto recibido y lo que `parseBankText` entendió de él.
class _Diagnosis extends StatelessWidget {
  const _Diagnosis({required this.event, required this.currency, required this.now});

  final CaptureEvent? event;
  final String currency;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final event = this.event;
    if (event == null) {
      return SurfaceCard(
        child: Text(
          'Todavía no ha llegado ningún texto. Lanza el atajo con un correo o prueba con un ejemplo.',
          style: AppType.subhead,
        ),
      );
    }
    final parsed = parseBankText(event.text, fallbackCurrency: currency, now: now);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Último texto (${event.sourceLabel})', style: AppType.footnote.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(event.text, maxLines: 8, overflow: TextOverflow.ellipsis, style: AppType.footnote),
          const SizedBox(height: 12),
          Text('Lo que se entendió', style: AppType.footnote.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (parsed == null)
            Text('No se reconoció ningún importe', style: AppType.body.copyWith(color: AppColors.danger))
          else ...[
            _Line('Importe', Fmt.money(Money(parsed.amountMinor, parsed.currency))),
            _Line('Tipo', parsed.direction == CaptureDirection.out ? 'Gasto' : 'Ingreso'),
            _Line('Comercio o persona', parsed.counterparty ?? '—'),
            _Line('Referencia', parsed.operationId ?? '—'),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppType.subhead)),
            Flexible(child: Text(value, textAlign: TextAlign.right, style: AppType.body)),
          ],
        ),
      );
}
