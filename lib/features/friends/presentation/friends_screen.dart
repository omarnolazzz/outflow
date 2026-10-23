import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/domain/money.dart';
import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../account/presentation/session_controller.dart';
import '../../shell/presentation/app_shell.dart';
import '../data/social_repository.dart';
import '../domain/balances.dart';
import '../domain/shared_expense.dart';
import 'add_friend_sheet.dart';
import 'friend_detail_screen.dart';
import 'friends_format.dart';
import 'friends_providers.dart';
import 'split_editor_screen.dart';

/// Pestaña Amigos: saldos, solicitudes, amigos y gastos compartidos.
class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final social = ref.watch(socialRepositoryProvider);
    final myUid = ref.watch(currentAccountProvider.select((a) => a?.uid));
    final friends = ref.watch(friendsProvider).value ?? const <Person>[];
    final incoming = ref.watch(incomingRequestsProvider).value ?? const <FriendRequest>[];
    final outgoing = ref.watch(outgoingRequestsProvider).value ?? const <FriendRequest>[];
    final expenses = [...?ref.watch(sharedExpensesProvider).value?.expenses]
      ..sort((a, b) => b.date.compareTo(a.date));
    final balances = {for (final b in ref.watch(balancesProvider)) b.friendUid: b};
    final total = totalsLabel(balances.values.toList());
    final friendUids = {for (final f in friends) f.uid};
    final others = [
      for (final uid in balances.keys)
        if (!friendUids.contains(uid))
          expenses.map((x) => x.people[uid]).whereType<Person>().firstOrNull ??
              Person(uid: uid, name: 'Amigo', email: ''),
    ];

    var order = 0;
    Widget e(Widget child) => Entrance(index: order++, child: child);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        primary: true,
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 12, bottom: shellBottomInset(context)),
        children: [
          e(Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
            child: Row(
              children: [
                Expanded(child: Text('Amigos', style: AppType.largeTitle)),
                if (social.available) const _AddMenu(),
              ],
            ),
          )),
          if (!social.available)
            e(Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SurfaceCard(
                child: Row(
                  children: [
                    const Icon(LucideIcons.users, color: AppColors.inkTertiary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Entra con tu cuenta de Google para dividir gastos con amigos.',
                        style: AppType.subhead,
                      ),
                    ),
                  ],
                ),
              ),
            ))
          else ...[
            if (total != null)
              e(Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(total, style: AppType.headline),
              )),
            if (friends.isEmpty && incoming.isEmpty && outgoing.isEmpty)
              e(Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SurfaceCard(
                  child: Text('Añade a tus amigos por su correo de Google.', style: AppType.subhead),
                ),
              )),
            if (incoming.isNotEmpty || outgoing.isNotEmpty) ...[
              e(const SectionHeader('Solicitudes')),
              for (final r in incoming)
                e(Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _IncomingRow(request: r),
                )),
              for (final r in outgoing)
                e(Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _PersonCard(person: r.to, trailing: const StatusPill('Pendiente')),
                )),
            ],
            if (friends.isNotEmpty) ...[
              e(const SectionHeader('Amigos')),
              for (final f in friends)
                e(Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _FriendRow(friend: f, balance: balances[f.uid]),
                )),
            ],
            // Saldos con quien no es tu amigo (p. ej. pagó otra persona en un
            // gasto que repartió un amigo): también se ven y se saldan.
            if (others.isNotEmpty) ...[
              e(const SectionHeader('Otras personas')),
              for (final p in others)
                e(Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _FriendRow(friend: p, balance: balances[p.uid]),
                )),
            ],
            if (expenses.isNotEmpty) ...[
              e(const SectionHeader('Gastos compartidos')),
              e(Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SurfaceCard(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  child: Column(
                    children: [for (final x in expenses) _HistoryRow(expense: x, myUid: myUid)],
                  ),
                ),
              )),
            ],
          ],
        ],
      ),
    );
  }
}

/// Botón "+" de la cabecera: añadir un amigo o dividir un gasto.
class _AddMenu extends StatelessWidget {
  const _AddMenu();

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Opciones',
        color: AppColors.surface,
        onSelected: (v) => v == 'split' ? showSplitEditor(context) : showAddFriendSheet(context),
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            value: 'add',
            child: Row(children: [
              const Icon(LucideIcons.userPlus, size: 18, color: AppColors.ink),
              const SizedBox(width: 10),
              Flexible(child: Text('Añadir amigo', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body)),
            ]),
          ),
          PopupMenuItem<String>(
            value: 'split',
            child: Row(children: [
              const Icon(LucideIcons.split, size: 18, color: AppColors.ink),
              const SizedBox(width: 10),
              Flexible(child: Text('Dividir un gasto', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body)),
            ]),
          ),
        ],
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(color: AppColors.fill, shape: BoxShape.circle),
          child: const Icon(LucideIcons.plus, size: 20, color: AppColors.ink),
        ),
      );
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, this.subtitle, this.subtitleColor, this.trailing, this.onTap});

  final Person person;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            PersonAvatar(person),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(person.name.isEmpty ? person.email : person.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body),
                  if (subtitle != null)
                    Text(subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.subhead.copyWith(color: subtitleColor ?? AppColors.inkSecondary)),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      );
}

class _IncomingRow extends ConsumerWidget {
  const _IncomingRow({required this.request});
  final FriendRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void answer(bool accept) => fireWrite(
          context,
          ref.read(socialRepositoryProvider).answer(request.id, accept: accept),
        );
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        children: [
          Row(children: [
            PersonAvatar(request.from),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.from.name.isEmpty ? request.from.email : request.from.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body),
                  Text(request.from.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.subhead.copyWith(color: AppColors.inkSecondary)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: PillButton(label: 'Aceptar', filled: true, onTap: () => answer(true))),
            const SizedBox(width: 10),
            Expanded(child: PillButton(label: 'Rechazar', onTap: () => answer(false))),
          ]),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.friend, required this.balance});
  final Person friend;
  final Balance? balance;

  @override
  Widget build(BuildContext context) {
    final s = splitBalance(balance);
    return _PersonCard(
      person: friend,
      subtitle: balanceLabel(balance),
      subtitleColor: s.owed.isNotEmpty
          ? AppColors.accent
          : s.owe.isNotEmpty
              ? AppColors.danger
              : AppColors.inkSecondary,
      trailing: const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.inkTertiary),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => FriendDetailScreen(friendUid: friend.uid)),
      ),
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.expense, required this.myUid});
  final SharedExpense expense;
  final String? myUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payer = expense.paidBy == myUid
        ? 'Pagaste tú'
        : 'Pagó ${expense.people[expense.paidBy]?.firstName ?? "otra persona"}';
    final me = myUid;
    return Pressable(
      // La misma hoja que en el detalle de un amigo: marcar pagos, Editar, Borrar.
      onTap: me == null ? null : () => showExpenseActions(context, ref, expense, me),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(expense.title.isEmpty ? 'Gasto' : expense.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.body),
                  Text('$payer · ${Fmt.dateShort(expense.date)}',
                      style: AppType.subhead.copyWith(color: AppColors.inkSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(Fmt.money(Money(expense.totalMinor, expense.currency)), style: AppType.body),
          ],
        ),
      ),
    );
  }
}
