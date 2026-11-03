import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/domain/money.dart';
import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../account/presentation/account_avatar.dart';
import '../../account/presentation/session_controller.dart';
import '../../notifications/domain/notification_rule.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../notifications/presentation/widgets/notification_rule_editor.dart';
import '../../wallet/data/payment_listener.dart';
import '../../wallet/domain/wallet_account.dart';
import '../../wallet/domain/wallet_settings.dart';
import '../../wallet/presentation/screens/accounts_screen.dart';
import '../../wallet/presentation/widgets/account_editor_sheet.dart';
import '../../wallet/presentation/wallet_providers.dart';
import 'apple_pay_guide_screen.dart';
import 'category_editor_screen.dart';
import 'google_pay_guide_screen.dart';

/// Cuenta y ajustes: cuenta de Google, moneda, sobrante, Face ID, avisos y
/// categorías. Aquí vivirán el atajo de Apple Pay (fase 2) y los amigos (fase 4).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _update(WalletSettings Function(WalletSettings) f) async {
    final repo = ref.read(walletSettingsRepositoryProvider);
    await repo.save(f(repo.read()));
  }

  Future<void> _toggleFaceId(bool on, String label) async {
    if (on) {
      // Se confirma con la cara antes de activarlo.
      final ok = await ref.read(biometricsProvider).authenticate('Activa el desbloqueo con $label');
      if (!ok) return;
    }
    HapticFeedback.selectionClick();
    await _update((s) => s.copyWith(faceIdEnabled: on));
  }

  Future<void> _pickCurrency(String current) async {
    final picked = await showModalBottomSheet<String>(
        useRootNavigator: true,
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text('Moneda principal', style: AppType.title2),
            ),
            for (final c in kSupportedCurrencies)
              ListTile(
                leading: SizedBox(width: 40, child: Center(child: Text(Fmt.symbol(c), style: AppType.headline))),
                title: Text(c, style: AppType.body),
                trailing: c == current ? const Icon(LucideIcons.check, color: AppColors.accent) : null,
                onTap: () => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
    await _update((s) => s.copyWith(currency: picked));
    if (mounted) await _warnIfAccountCurrencyDiffers(picked);
  }

  /// Los movimientos nuevos van en la moneda principal; una cuenta por defecto en
  /// otra moneda dejaría de moverse sin que se note. Se avisa y, si la cuenta no
  /// tiene movimientos, se ofrece pasarla a la moneda nueva.
  Future<void> _warnIfAccountCurrencyDiffers(String currency) async {
    final WalletAccount account;
    final bool used;
    try {
      final found = defaultAccountOf(await ref.read(accountRepositoryProvider).watchAll().first);
      if (found == null || found.currency == currency) return;
      account = found;
      used = await ref.read(accountActionsProvider).hasMovements(found.id);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final action = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Tu cuenta sigue en ${account.currency}'),
        content: Text(
          used
              ? 'Tu cuenta «${account.name}» está en ${account.currency} y ya tiene movimientos, así que no se puede '
                  'cambiar de moneda. Lo que registres en $currency no la moverá: crea una cuenta en $currency para '
                  'llevar ese saldo.'
              : 'Tu cuenta «${account.name}» está en ${account.currency}, pero lo que registres en $currency no la '
                  'moverá. Como todavía no tiene movimientos, puedes pasarla a $currency.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(used ? 'Entendido' : 'Dejarla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(used ? 'Crear cuenta' : 'Cambiar a $currency'),
          ),
        ],
      ),
    );
    if (action != true || !mounted) return;
    if (used) {
      await showAccountEditor(context);
    } else {
      await ref.read(accountActionsProvider).setCurrencyIfUnused(account.id, currency);
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text('Tus datos siguen guardados en este teléfono. Vuelve a entrar con tu cuenta de Google cuando quieras.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await ref.read(sessionControllerProvider.notifier).signOut();
  }

  Future<void> _eraseEverything() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar toda la información?'),
        content: const Text(
          'Se borran tus gastos, ingresos, suscripciones, categorías propias y ajustes de este teléfono, '
          'y tus amistades y los gastos compartidos que creaste. Volverás a la configuración inicial con '
          'tu misma cuenta de Google.\n\nNo se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar todo', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    HapticFeedback.heavyImpact();
    Navigator.of(context).popUntil((r) => r.isFirst);
    await ref.read(sessionControllerProvider.notifier).eraseEverything();
  }

  Future<void> _saveRule(NotificationRule previous, NotificationRule rule) async {
    await ref.read(notificationSettingsRepositoryProvider).saveGlobalRule(rule);
    if (rule.enabled && !previous.enabled) await ref.read(requestNotificationPermissionProvider)();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(currentAccountProvider);
    final settings = ref.watch(walletSettingsProvider).value ?? const WalletSettings();
    final rule = ref.watch(globalRuleProvider).value ?? NotificationRule.defaults;
    final session = ref.read(sessionControllerProvider.notifier);
    final bioLabel = session.biometricsLabel;

    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return SheetScaffold(
      title: 'Ajustes',
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.paddingOf(context).bottom + 32),
        children: [
          if (account != null)
            e(SurfaceCard(
              child: Row(
                children: [
                  AccountAvatar(account: account, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(account.displayName.isEmpty ? account.email : account.displayName, style: AppType.headline),
                        Text(account.email, style: AppType.footnote),
                      ],
                    ),
                  ),
                  const StatusPill('Google'),
                ],
              ),
            )),
          e(const _Header('Wallet')),
          e(_Group(children: [
            _Tile(
              icon: LucideIcons.coins,
              label: 'Moneda principal',
              trailing: Text('${Fmt.symbol(settings.currency)} ${settings.currency}', style: AppType.body.copyWith(color: AppColors.inkSecondary)),
              onTap: () => _pickCurrency(settings.currency),
            ),
            _Tile(
              icon: LucideIcons.arrowRightLeft,
              label: 'Lo que sobra pasa al mes siguiente',
              trailing: Switch.adaptive(
                key: const ValueKey('carryOver'),
                value: settings.carryOver,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  _update((s) => s.copyWith(carryOver: v));
                },
              ),
            ),
            _Tile(
              icon: LucideIcons.landmark,
              label: 'Cuentas',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountsScreen())),
            ),
            _Tile(
              icon: LucideIcons.tags,
              label: 'Categorías',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CategoryEditorScreen())),
            ),
            // iPhone: atajo de Apple Pay. Android: avisos de Google Pay y bancos.
            _Tile(
              icon: LucideIcons.smartphoneNfc,
              label: isAndroidDevice ? 'Registrar pagos con Google Pay' : 'Registrar pagos con Apple Pay',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => isAndroidDevice ? const GooglePayGuideScreen() : const ApplePayGuideScreen(),
              )),
              last: true,
            ),
          ])),
          e(const _Header('Seguridad')),
          e(_Group(children: [
            _Tile(
              icon: LucideIcons.scanFace,
              label: 'Desbloquear con $bioLabel',
              subtitle: session.biometricsAvailable ? 'Solo al pulsar el botón, nunca automático.' : 'No disponible en este dispositivo.',
              trailing: Switch.adaptive(
                value: settings.faceIdEnabled && session.biometricsAvailable,
                onChanged: session.biometricsAvailable ? (v) => _toggleFaceId(v, bioLabel) : null,
              ),
              last: true,
            ),
          ])),
          e(const _Header('Avisos')),
          e(SurfaceCard(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NotificationRuleEditor(rule: rule, onChanged: (r) => _saveRule(rule, r)),
                const SizedBox(height: 8),
                PillButton(
                  label: 'Enviar aviso de prueba',
                  icon: LucideIcons.bell,
                  onTap: () async {
                    final service = ref.read(notificationServiceProvider);
                    await service.requestPermission();
                    HapticFeedback.lightImpact();
                    await service.showTest();
                  },
                ),
              ],
            ),
          )),
          const SizedBox(height: 24),
          if (account != null)
            e(Center(
              child: Pressable(
                onTap: _eraseEverything,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    'Borrar toda la información',
                    style: AppType.callout.copyWith(color: AppColors.danger),
                  ),
                ),
              ),
            )),
          if (account != null)
            e(Center(
              child: Pressable(
                onTap: _signOut,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    'Cerrar sesión',
                    style: AppType.callout.copyWith(color: AppColors.danger, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            )),
          const SizedBox(height: 8),
          e(Center(
            child: Text(
              'Outflow · tus gastos se guardan cifrados en este teléfono',
              style: AppType.caption.copyWith(color: AppColors.inkTertiary),
            ),
          )),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 24, 6, 8),
        child: Text(text.toUpperCase(), style: AppType.caption.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.4)),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      SurfaceCard(padding: const EdgeInsets.symmetric(vertical: 2), child: Column(children: children));
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, this.subtitle, this.trailing, this.onTap, this.last = false});

  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            border: last ? null : const Border(bottom: BorderSide(color: AppColors.separator, width: 0.6)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: ShapeDecoration(
                  color: AppColors.accentSoft,
                  shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(9)),
                ),
                child: Icon(icon, size: 17, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppType.body),
                    if (subtitle != null) Text(subtitle!, style: AppType.footnote),
                  ],
                ),
              ),
              ?trailing,
              if (trailing == null && onTap != null)
                const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.inkTertiary),
            ],
          ),
        ),
      );
}
