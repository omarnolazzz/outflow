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
import '../../capture/data/capture_sources_repository.dart';
import '../../wallet/data/payment_listener.dart';
import '../../wallet/domain/wallet_account.dart';
import '../../wallet/presentation/wallet_providers.dart';

/// Android: captura automática. Lee en silencio las notificaciones con dinero de
/// las apps que actives y las deja por revisar en Outflow.
class GooglePayGuideScreen extends ConsumerStatefulWidget {
  const GooglePayGuideScreen({super.key});

  @override
  ConsumerState<GooglePayGuideScreen> createState() => _GooglePayGuideScreenState();
}

class _GooglePayGuideScreenState extends ConsumerState<GooglePayGuideScreen> with WidgetsBindingObserver {
  bool? _enabled;
  List<CaptureApp> _apps = const [];
  Set<String> _on = {};
  Map<String, String> _sources = const {};

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
    final listener = ref.read(paymentListenerProvider);
    final enabled = await listener.isEnabled();
    final apps = await listener.seenApps();
    final on = await listener.enabledApps();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _apps = apps;
      _on = on;
      _sources = ref.read(captureSourcesRepositoryProvider).read();
    });
  }

  Future<void> _toggle(CaptureApp app, bool value) async {
    HapticFeedback.selectionClick();
    setState(() => value ? _on = {..._on, app.package} : _on = {..._on}..remove(app.package));
    await ref.read(paymentListenerProvider).setEnabled(app.package, value);
  }

  Future<void> _assign(CaptureApp app, String accountId) async {
    setState(() => _sources = {..._sources, app.package: accountId});
    await ref.read(captureSourcesRepositoryProvider).assign(app.package, accountId);
  }

  @override
  Widget build(BuildContext context) {
    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);
    final enabled = _enabled ?? false;
    final accounts = (ref.watch(accountsProvider).value ?? const <WalletAccount>[]).where((a) => !a.archived).toList();

    return SheetScaffold(
      title: 'Captura automática',
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
          e(Text('Captura automática de pagos', textAlign: TextAlign.center, style: AppType.title1)),
          const SizedBox(height: 8),
          e(Text(
            'Cuando una app que actives te avise de un pago, Outflow lo deja en silencio como '
            '"por revisar". Lo confirmas cuando abras la app.',
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
                    Expanded(child: Text('Permiso para leer notificaciones', style: AppType.headline)),
                    if (_enabled != null)
                      StatusPill(
                        enabled ? 'Activado' : 'Desactivado',
                        tone: enabled ? PillTone.accent : PillTone.neutral,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Solo se guardan los avisos con un importe, y solo de las apps activadas abajo. '
                  'El resto se ignora y nada sale de tu teléfono.',
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
              'En la lista, activa "Outflow" y vuelve aquí.',
              textAlign: TextAlign.center,
              style: AppType.caption,
            )),
          ],
          if (_apps.isNotEmpty) ...[
            const SizedBox(height: 24),
            e(Text('Apps', style: AppType.headline)),
            const SizedBox(height: 4),
            e(Text(
              'Si tu banco no aparece, espera a que te llegue un aviso con un importe: saldrá aquí.',
              style: AppType.caption,
            )),
            const SizedBox(height: 10),
            for (final app in _apps) ...[
              e(_AppRow(
                app: app,
                on: _on.contains(app.package),
                accounts: accounts,
                accountId: accounts.any((a) => a.id == _sources[app.package]) ? _sources[app.package] : null,
                onToggle: (v) => _toggle(app, v),
                onAccount: (id) => _assign(app, id),
              )),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.on,
    required this.accounts,
    required this.accountId,
    required this.onToggle,
    required this.onAccount,
  });

  final CaptureApp app;
  final bool on;
  final List<WalletAccount> accounts;
  final String? accountId;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onAccount;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(app.label, style: AppType.headline)),
              Switch(
                key: ValueKey('switch:${app.package}'),
                value: on,
                activeThumbColor: AppColors.onAccent,
                activeTrackColor: AppColors.accent,
                onChanged: onToggle,
              ),
            ],
          ),
          if (on && accounts.isNotEmpty)
            DropdownButton<String>(
              key: ValueKey('account:${app.package}'),
              value: accountId,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              hint: Text('Cuenta: la principal', style: AppType.subhead),
              items: [
                for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (id) {
                if (id != null) onAccount(id);
              },
            ),
        ],
      ),
    );
  }
}
