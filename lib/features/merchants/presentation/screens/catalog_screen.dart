import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/notion_widgets.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../subscriptions/presentation/screens/subscription_form_screen.dart';
import '../../domain/entities/merchant.dart';
import '../merchant_providers.dart';
import '../widgets/merchant_avatar.dart';
import 'create_merchant_screen.dart';

/// Paso 1 de "Nueva suscripción": elegir el comercio.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String _query = '';

  void _pick(Merchant m) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SubscriptionFormScreen.create(merchant: m)),
      );

  void _createCustom() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CreateMerchantScreen(initialName: _query.trim())),
      );

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(merchantsProvider).value ?? const <Merchant>[];
    final q = _normalize(_query);
    final filtered = q.isEmpty ? all : all.where((m) => _normalize(m.name).contains(q)).toList();

    final custom = filtered.where((m) => m.isCustom).toList();
    final byCategory = <SpendCategory, List<Merchant>>{};
    for (final m in filtered.where((m) => !m.isCustom)) {
      byCategory.putIfAbsent(m.category, () => []).add(m);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva suscripción'),
        leading: IconButton(
          tooltip: 'Cerrar',
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Buscar Netflix, Telcel, iCloud…',
                  prefixIcon: Icon(LucideIcons.search, size: 18, color: AppColors.inkTertiary),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Pressable(
                onTap: _createCustom,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Icon(LucideIcons.plus, size: 18, color: AppColors.ink),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _query.trim().isEmpty
                                  ? 'Crear comercio personalizado'
                                  : 'Crear “${_query.trim()}”',
                              style: AppType.bodyStrong,
                            ),
                            Text('Con su propio icono y reglas de cobro', style: AppType.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (custom.isNotEmpty) ..._section('Tus comercios', custom),
          for (final c in SpendCategory.values)
            if (byCategory[c] != null) ..._section(c.label, byCategory[c]!),
          if (filtered.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No está en el catálogo. Créalo arriba en segundos.',
                  style: AppType.body.copyWith(color: AppColors.inkTertiary),
                ),
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
        ],
      ),
    );
  }

  List<Widget> _section(String title, List<Merchant> items) => [
        SliverToBoxAdapter(child: SectionLabel(title, padding: const EdgeInsets.fromLTRB(20, 22, 20, 6))),
        SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, i) {
            final m = items[i];
            return Pressable(
              onTap: () => _pick(m),
              borderRadius: BorderRadius.zero,
              scale: 0.99,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                child: Row(
                  children: [
                    MerchantAvatar(logo: m.logo, name: m.name, size: 32),
                    const SizedBox(width: 12),
                    Expanded(child: Text(m.name, style: AppType.body)),
                    const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.inkTertiary),
                  ],
                ),
              ),
            );
          },
        ),
      ];

  /// Búsqueda sin acentos ni mayúsculas ("musica" encuentra "Música").
  static String _normalize(String s) {
    const from = 'áàäâéèëêíìïîóòöôúùüûñ';
    const to = 'aaaaeeeeiiiioooouuuun';
    final lower = s.toLowerCase();
    final b = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      b.write(i == -1 ? ch : to[i]);
    }
    return b.toString();
  }
}
