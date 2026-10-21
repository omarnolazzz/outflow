import 'dart:async';

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
