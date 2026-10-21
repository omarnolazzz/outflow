import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/notion_widgets.dart';
import '../../domain/notification_rule.dart';
import '../notification_providers.dart';
import '../widgets/notification_rule_editor.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _saveRule(NotificationRule previous, NotificationRule rule) async {
    await ref.read(notificationSettingsRepositoryProvider).saveGlobalRule(rule);
    if (rule.enabled && !previous.enabled) {
      await ref.read(notificationServiceProvider).requestPermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rule = ref.watch(globalRuleProvider).value ?? NotificationRule.defaults;

    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        leading: IconButton(
          tooltip: 'Atrás',
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(12, 0, 12, MediaQuery.paddingOf(context).bottom + 32),
        children: [
          e(const SectionLabel('Recordatorios generales', padding: EdgeInsets.fromLTRB(8, 16, 8, 4))),
          e(
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Text(
                'Se aplican a todas las suscripciones que no tengan los suyos propios.',
                style: AppType.caption,
              ),
            ),
          ),
          e(NotificationRuleEditor(rule: rule, onChanged: (r) => _saveRule(rule, r))),
          const SizedBox(height: 12),
          e(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlineAction(
                  label: 'Enviar aviso de prueba',
                  icon: LucideIcons.bell,
                  onTap: () async {
                    final service = ref.read(notificationServiceProvider);
                    await service.requestPermission();
                    HapticFeedback.lightImpact();
                    await service.showTest();
                  },
                ),
              ),
            ),
          ),
          e(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: NotionCallout(
                emoji: '🔒',
                child: Text(
                  'Tus datos se guardan cifrados solo en este dispositivo. Outflow no tiene servidor '
                  'ni accede a tus cuentas bancarias.',
                  style: AppType.body.copyWith(color: AppColors.inkSecondary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
