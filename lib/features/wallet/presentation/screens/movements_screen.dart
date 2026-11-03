import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/di/core_providers.dart';
import '../../../../core/domain/billing_cycle.dart';
import '../../../../core/domain/money.dart';
import '../../../../core/motion/motion_widgets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/segmented_control.dart';
import '../../../../core/widgets/surface_card.dart';
import '../../../merchants/presentation/merchant_providers.dart';
import '../../../shell/presentation/app_shell.dart';
import '../../../subscriptions/presentation/subscription_providers.dart';
import '../../domain/category.dart';
import '../../domain/movement.dart';
import '../wallet_providers.dart';
import '../widgets/category_icon.dart';
import '../widgets/movement_row.dart';
import '../widgets/movement_sheet.dart';

enum _Filter { all, expenses, income }

/// Todos los gastos e ingresos, agrupados por día, con buscador y filtros.
class MovementsScreen extends ConsumerStatefulWidget {
  const MovementsScreen({super.key});

  @override
  ConsumerState<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends ConsumerState<MovementsScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _delete(Movement m) async {
    final actions = ref.read(walletActionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final deleted = await actions.delete(m.id);
    if (deleted == null) return;
    HapticFeedback.heavyImpact();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Movimiento borrado.'),
        action: SnackBarAction(label: 'Deshacer', onPressed: () => actions.restore(deleted)),
      ));
  }

  String _dayLabel(DateTime day, DateTime today) {
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    final long = Fmt.dateLong(day);
    // "lunes, 18 de octubre de 2026" → "Lunes 18 de octubre" (el año solo si no es el actual).
    final noYear = day.year == today.year ? long.replaceAll(RegExp(r' de \d{4}$'), '') : long;
    final s = noYear.replaceFirst(',', '');
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(ref.watch(nowProvider));
    final all = ref.watch(movementsProvider).value ?? const <Movement>[];
    final categories = ref.watch(categoryIndexProvider);
    final merchants = ref.watch(merchantIndexProvider);
    final subs = {for (final s in ref.watch(subscriptionsProvider).value ?? const []) s.id: s};
    final query = _search.text.trim().toLowerCase();

    final filtered = all.where((m) {
      if (_filter == _Filter.expenses && !m.isExpense) return false;
      if (_filter == _Filter.income && m.isExpense) return false;
      if (_category != null && m.categoryId != _category) return false;
      if (query.isEmpty) return true;
      final cat = categories[m.categoryId]?.name ?? '';
      return '${m.title} ${m.note} $cat'.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
      });

    final groups = <DateTime, List<Movement>>{};
    for (final m in filtered) {
      groups.putIfAbsent(dateOnly(m.date), () => []).add(m);
    }
    final usedCategories = {for (final m in all) m.categoryId}
        .map((id) => categories[id])
        .whereType<Category>()
        .toList();

    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        primary: true,
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 12, bottom: shellBottomInset(context)),
        children: [
          e(Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text('Movimientos', style: AppType.largeTitle),
          )),
          e(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: AppType.body,
              decoration: InputDecoration(
                hintText: 'Buscar',
                prefixIcon: const Icon(LucideIcons.search, size: 18, color: AppColors.inkTertiary),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar búsqueda',
                        icon: const Icon(LucideIcons.x, size: 16, color: AppColors.inkTertiary),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          )),
          const SizedBox(height: 12),
          e(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedControl<_Filter>(
              values: _Filter.values,
              selected: _filter,
              label: (f) => switch (f) {
                _Filter.all => 'Todos',
                _Filter.expenses => 'Gastos',
                _Filter.income => 'Ingresos',
              },
              onChanged: (f) => setState(() => _filter = f),
            ),
          )),
          if (usedCategories.length > 1) ...[
            const SizedBox(height: 10),
            e(SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final c in usedCategories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: Icon(categoryIcon(c.icon), size: 16, color: Color(c.color)),
                        label: Text(c.name),
                        selected: _category == c.id,
                        showCheckmark: false,
                        selectedColor: AppColors.accentSoft,
                        backgroundColor: AppColors.surface,
                        side: BorderSide(color: _category == c.id ? AppColors.accent : AppColors.separator),
                        shape: const StadiumBorder(),
                        labelStyle: AppType.footnote.copyWith(color: AppColors.ink),
                        onSelected: (v) => setState(() => _category = v ? c.id : null),
                      ),
                    ),
                ],
              ),
            )),
          ],
          if (groups.isEmpty)
            e(Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: SurfaceCard(
                child: Text(
                  all.isEmpty ? 'Aún no hay movimientos. Toca + para registrar el primero.' : 'Nada coincide con tu búsqueda.',
                  style: AppType.subhead,
                ),
              ),
            )),
          for (final MapEntry(key: day, value: items) in groups.entries) ...[
            e(Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
              child: Row(
                children: [
                  Expanded(child: Text(_dayLabel(day, today), style: AppType.headline)),
                  Text(_dayTotal(items), style: AppType.footnote),
                ],
              ),
            )),
            e(Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SurfaceCard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (final m in items)
                      Dismissible(
                        key: ValueKey(m.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: AppColors.dangerSoft,
                          child: const Icon(LucideIcons.trash2, color: AppColors.danger),
                        ),
                        // Tu parte de un gasto compartido se gestiona desde Amigos.
                        confirmDismiss: (_) async => m.origin != MovementOrigin.split,
                        onDismissed: (_) => _delete(m),
                        child: MovementRow(
                          movement: m,
                          category: categories[m.categoryId],
                          merchant: merchants[subs[m.subscriptionId]?.merchantId],
                          onTap: () => showMovementSheet(context, editing: m),
                        ),
                      ),
                  ],
                ),
              ),
            )),
          ],
        ],
      ),
    );
  }

  /// Neto del día en la moneda del primer movimiento (solo informativo).
  String _dayTotal(List<Movement> items) {
    final counted = items.where((m) => m.countsInWallet).toList();
    if (counted.isEmpty) return '';
    final currency = counted.first.amount.currency;
    final net = counted.where((m) => m.amount.currency == currency).fold<int>(0, (s, m) => s + m.signedMinor);
    final money = Fmt.money(Money(net.abs(), currency));
    return net < 0 ? '−$money' : '+$money';
  }
}
