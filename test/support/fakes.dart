import 'dart:async';

import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/friends/data/social_repository.dart';
import 'package:outflow/features/friends/domain/shared_expense.dart';
import 'package:outflow/features/friends/domain/split_movements.dart';
import 'package:outflow/features/subscriptions/domain/entities/subscription.dart';
import 'package:outflow/features/subscriptions/domain/subscription_repository.dart';
import 'package:outflow/features/wallet/data/hive_movement_repository.dart';
import 'package:outflow/features/wallet/data/wallet_settings_repository.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';

/// Ajustes de la wallet en memoria.
class MemorySettings implements WalletSettingsRepository {
  MemorySettings([this.value = const WalletSettings()]);
  WalletSettings value;
  final _c = StreamController<WalletSettings>.broadcast();
  @override
  WalletSettings read() => value;
  @override
  Future<void> save(WalletSettings s) async => _c.add(value = s);
  @override
  Stream<WalletSettings> watch() async* {
    yield value;
    yield* _c.stream;
  }
}

/// Movimientos en memoria.
class MemoryMovements implements MovementRepository {
  MemoryMovements([List<Movement> initial = const []]) : _items = {for (final m in initial) m.id: m};
  final Map<String, Movement> _items;
  final _c = StreamController<List<Movement>>.broadcast();

  List<Movement> get saved => _items.values.toList();
  void _emit() => _c.add(saved);

  @override
  Future<void> save(Movement m) async {
    _items[m.id] = m;
    _emit();
  }

  @override
  Future<void> saveAll(Iterable<Movement> ms) async {
    for (final m in ms) {
      _items[m.id] = m;
    }
    _emit();
  }

  @override
  Future<void> delete(String id) async {
    _items.remove(id);
    _emit();
  }

  @override
  Future<void> deleteAll(Iterable<String> ids) async {
    ids.forEach(_items.remove);
    _emit();
  }

  @override
  Stream<List<Movement>> watchAll() async* {
    yield saved;
    yield* _c.stream;
  }
}

/// Suscripciones en memoria.
class MemorySubscriptions implements SubscriptionRepository {
  MemorySubscriptions([List<Subscription> initial = const []]) : _items = {for (final s in initial) s.id: s};
  final Map<String, Subscription> _items;
  final _c = StreamController<List<Subscription>>.broadcast();

  List<Subscription> get saved => _items.values.toList();

  @override
  Future<Subscription?> byId(String id) async => _items[id];
  @override
  Future<void> save(Subscription s) async {
    _items[s.id] = s;
    _c.add(saved);
  }

  @override
  Future<void> delete(String id) async {
    _items.remove(id);
    _c.add(saved);
  }

  @override
  Stream<List<Subscription>> watchAll() async* {
    yield saved;
    yield* _c.stream;
  }
}

/// Amigos y gastos compartidos en memoria.
class MemorySocial implements SocialRepository {
  MemorySocial({
    this.available = true,
    List<Person> friends = const [],
    List<FriendRequest> incoming = const [],
    List<FriendRequest> outgoing = const [],
    List<SharedExpense> expenses = const [],
    this.addResult = AddFriendResult.notOnOutflow,
  })  : friends = [...friends],
        incoming = [...incoming],
        outgoing = [...outgoing],
        expenses = [...expenses];

  @override
  final bool available;
  final List<Person> friends;
  final List<FriendRequest> incoming;
  final List<FriendRequest> outgoing;
  final List<SharedExpense> expenses;
  AddFriendResult addResult;
  final added = <String>[];

  final _friends = StreamController<List<Person>>.broadcast();
  final _incoming = StreamController<List<FriendRequest>>.broadcast();
  final _outgoing = StreamController<List<FriendRequest>>.broadcast();
  final _expenses = StreamController<ExpensesSnapshot>.broadcast();

  ExpensesSnapshot get _snapshot => ExpensesSnapshot([...expenses], fromCache: false);

  @override
  Future<void> publishProfile(Account me) async {}
  @override
  Stream<List<Person>> watchFriends() async* {
    yield [...friends];
    yield* _friends.stream;
  }

  @override
  Stream<List<FriendRequest>> watchIncoming() async* {
    yield [...incoming];
    yield* _incoming.stream;
  }

  @override
  Stream<List<FriendRequest>> watchOutgoing() async* {
    yield [...outgoing];
    yield* _outgoing.stream;
  }

  @override
  Future<AddFriendResult> addFriend(String email) async {
    added.add(email);
    return addResult;
  }

  @override
  Future<void> answer(String requestId, {required bool accept}) async {
    final r = incoming.firstWhere((x) => x.id == requestId);
    incoming.remove(r);
    if (accept) friends.add(r.from);
    _incoming.add([...incoming]);
    _friends.add([...friends]);
  }

  @override
  Stream<ExpensesSnapshot> watchExpenses() async* {
    yield _snapshot;
    yield* _expenses.stream;
  }

  @override
  Future<void> saveExpense(SharedExpense e) async {
    expenses
      ..removeWhere((x) => x.id == e.id)
      ..add(e);
    _expenses.add(_snapshot);
  }

  /// Como Firestore: todo menos `settled`, que solo pierde [unsettle].
  @override
  Future<void> updateExpense(SharedExpense e, {Set<String> unsettle = const {}}) async {
    final i = expenses.indexWhere((x) => x.id == e.id);
    final current = expenses[i];
    expenses[i] = e.copyWith(settled: {...current.settled}..removeWhere((k, _) => unsettle.contains(k)));
    _expenses.add(_snapshot);
  }

  @override
  Future<void> deleteExpense(String id) async {
    expenses.removeWhere((x) => x.id == id);
    _expenses.add(_snapshot);
  }

  @override
  Future<void> settle(String expenseId, String debtorUid) async {
    final i = expenses.indexWhere((x) => x.id == expenseId);
    final e = expenses[i];
    expenses[i] = e.copyWith(settled: {...e.settled, debtorUid: Settlement(by: debtorUid, at: DateTime(2026, 10, 20))});
    _expenses.add(_snapshot);
  }

  int forgetCalls = 0;

  @override
  Future<void> forgetMe() async => forgetCalls++;
}
