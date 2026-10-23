import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/money.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../account/presentation/session_controller.dart';
import '../domain/shared_expense.dart';
import 'friends_format.dart';
import 'friends_providers.dart';
import 'split_editor_screen.dart';

/// Saldo y gastos compartidos con un amigo; desde aquí se salda.
class FriendDetailScreen extends ConsumerStatefulWidget {
  const FriendDetailScreen({super.key, required this.friendUid});
  final String friendUid;

  @override
  ConsumerState<FriendDetailScreen> createState() => _FriendDetailScreenState();
}

class _FriendDetailScreenState extends ConsumerState<FriendDetailScreen> {
  /// Quién debe en este gasto entre tú y el amigo (null si no hay deuda entre los dos).
  String? _debtor(SharedExpense e, String me) {
    final f = widget.friendUid;
    if (e.paidBy == me && e.debtors.contains(f)) return f;
    if (e.paidBy == f && e.debtors.contains(me)) return me;
    return null;
  }

  Future<void> _settleAll(String me, Person friend, List<SharedExpense> pending) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Saldar todo con ${friend.firstName}?'),
        content: Text(pending.length == 1
            ? 'Se marcará como pagado 1 gasto.'
            : 'Se marcarán como pagados ${pending.length} gastos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Saldar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = ref.read(socialRepositoryProvider);
    // Sin esperar: offline las escrituras no terminan; los streams se actualizan solos.
    for (final e in pending) {
      fireWrite(context, repo.settle(e.id, _debtor(e, me)!));
    }
  }

  Future<void> _openExpense(SharedExpense e, String me) async {
    final debtor = _debtor(e, me);
    final canDelete = e.createdBy == me;
    final canSettle = debtor != null && !e.isSettled(debtor);
    // Ya pagado y de otro: no hay nada que hacer, no se abre una hoja vacía.
    if (!canSettle && !canDelete) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canSettle)
              ListTile(title: const Text('Marcar como pagado'), onTap: () => Navigator.pop(ctx, 'settle')),
            if (canDelete)
              ListTile(title: const Text('Editar'), onTap: () => Navigator.pop(ctx, 'edit')),
            if (canDelete)
              ListTile(
                title: const Text('Borrar', style: TextStyle(color: AppColors.danger)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final repo = ref.read(socialRepositoryProvider);
    if (action == 'settle' && debtor != null) {
      fireWrite(context, repo.settle(e.id, debtor));
    } else if (action == 'edit') {
      await showSplitEditor(context, editing: e);
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Borrar este gasto?'),
          content: const Text('Se borra para todos los que participan.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
          ],
        ),
      );
      if (ok == true && mounted) fireWrite(context, repo.deleteExpense(e.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentAccountProvider.select((a) => a?.uid)) ?? '';
    final all = ref.watch(sharedExpensesProvider).value?.expenses ?? const <SharedExpense>[];
    final friends = ref.watch(friendsProvider).value ?? const <Person>[];
    final balance = ref.watch(balancesProvider).where((b) => b.friendUid == widget.friendUid).firstOrNull;

    final shared = all.where((e) => _debtor(e, me) != null).toList()..sort((a, b) => b.date.compareTo(a.date));
    final friend = friends.where((f) => f.uid == widget.friendUid).firstOrNull ??
        all.map((e) => e.people[widget.friendUid]).whereType<Person>().firstOrNull ??
        Person(uid: widget.friendUid, name: 'Amigo', email: '');
    final pending = [
      for (final e in shared)
        if (!e.isSettled(_debtor(e, me)!)) e,
    ];
    final s = splitBalance(balance);

    return SheetScaffold(
      title: friend.name.isEmpty ? friend.email : friend.firstName,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SurfaceCard(
            child: Column(
              children: [
                PersonAvatar(friend, size: 56),
                const SizedBox(height: 12),
                Text(
                  balanceLabel(balance),
                  textAlign: TextAlign.center,
                  style: AppType.title2.copyWith(
                    color: s.owed.isNotEmpty
                        ? AppColors.accent
                        : s.owe.isNotEmpty
                            ? AppColors.danger
                            : AppColors.ink,
                  ),
                ),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  PrimaryButton(label: 'Saldar todo', onTap: () => _settleAll(me, friend, pending)),
                ],
              ],
            ),
          ),
          if (shared.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 26, 4, 10),
              child: Text('Gastos', style: AppType.title2),
            ),
            for (final e in shared)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SurfaceCard(
                  onTap: () => _openExpense(e, me),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title.isEmpty ? 'Gasto' : e.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body),
                            Text(
                              'Tu parte ${Fmt.money(Money(e.shareOf(me), e.currency))} · '
                              '${e.paidBy == me ? 'Pagaste tú' : 'Pagó ${friend.firstName}'}',
                              style: AppType.subhead.copyWith(color: AppColors.inkSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      e.isSettled(_debtor(e, me)!)
                          ? const StatusPill('Pagado', tone: PillTone.accent)
                          : const StatusPill('Pendiente'),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
