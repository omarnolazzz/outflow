import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/core/storage/local_store.dart';
import 'package:outflow/features/wallet/data/hive_account_repository.dart';
import 'package:outflow/features/wallet/domain/account_balances.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/expense_hints.dart';
import 'package:outflow/features/wallet/domain/month_summary.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/payment_match.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';

final _day = DateTime(2026, 10, 10);
var _seq = 0;

WalletAccount acc(
  String id, {
  String currency = 'PEN',
  int initial = 0,
  bool isDefault = false,
  bool archived = false,
}) =>
    WalletAccount(
      id: id,
      name: id,
      type: AccountType.bank,
      currency: currency,
      initialMinor: initial,
      initialDate: _day,
      isDefault: isDefault,
      archived: archived,
    );

Movement mv(
  MovementKind kind,
  int minor, {
  String currency = 'PEN',
  String? account,
  String? to,
  bool incoming = false,
  int? received,
  int? adjustment,
  int? paid,
  MovementOrigin origin = MovementOrigin.manual,
  String title = '',
  DateTime? date,
  DateTime? createdAt,
}) =>
    Movement(
      id: 'm${_seq++}',
      kind: kind,
      amount: Money(minor, currency),
      categoryId: kind == MovementKind.income ? 'salary' : 'food',
      date: date ?? _day,
      createdAt: createdAt ?? date ?? _day,
      title: title,
      origin: origin,
      accountId: account,
      toAccountId: to,
      transferIncoming: incoming,
      receivedMinor: received,
      adjustmentMinor: adjustment,
      paidMinor: paid,
    );

void main() {
  final a = acc('A', isDefault: true);
  final b = acc('B');
  final usd = acc('U', currency: 'USD');

  group('accountEffectMinor', () {
    test('ingreso suma y gasto resta en su cuenta; en otra cuenta, 0', () {
      expect(accountEffectMinor(mv(MovementKind.income, 500, account: 'B'), 'B', 'A'), 500);
      expect(accountEffectMinor(mv(MovementKind.expense, 500, account: 'B'), 'B', 'A'), -500);
      expect(accountEffectMinor(mv(MovementKind.expense, 500, account: 'B'), 'A', 'A'), 0);
    });

    test('un movimiento antiguo sin cuenta es de la cuenta por defecto', () {
      final old = mv(MovementKind.expense, 500);
      expect(accountEffectMinor(old, 'A', 'A'), -500);
      expect(accountEffectMinor(old, 'B', 'A'), 0);
    });

    test('un cobro de suscripción no mueve ninguna cuenta', () {
      final charge = mv(MovementKind.expense, 2990, account: 'A', origin: MovementOrigin.subscription);
      expect(accountEffectMinor(charge, 'A', 'A'), 0);
    });

    test('gasto con paidMinor: sale lo que salió de verdad, también 0', () {
      expect(accountEffectMinor(mv(MovementKind.expense, 2500, account: 'A', paid: 10000), 'A', 'A'), -10000);
      expect(accountEffectMinor(mv(MovementKind.expense, 2500, account: 'A', paid: 0), 'A', 'A'), 0,
          reason: 'pagó un amigo: la cuenta no cambia');
    });

    test('ajuste: su diferencia con signo, solo en su cuenta', () {
      final adj = mv(MovementKind.adjustment, 800, account: 'B', adjustment: -800);
      expect(accountEffectMinor(adj, 'B', 'A'), -800);
      expect(accountEffectMinor(adj, 'A', 'A'), 0);
    });

    test('transferencia: resta en origen, suma en destino, 0 en terceras', () {
      final t = mv(MovementKind.transfer, 10000, account: 'A', to: 'B');
      expect(accountEffectMinor(t, 'A', 'A'), -10000);
      expect(accountEffectMinor(t, 'B', 'A'), 10000);
      expect(accountEffectMinor(t, 'C', 'A'), 0);
    });

    test('transferencia con receivedMinor: el destino recibe ese importe', () {
      final t = mv(MovementKind.transfer, 10000, account: 'A', to: 'U', received: 2700);
      expect(accountEffectMinor(t, 'A', 'A'), -10000);
      expect(accountEffectMinor(t, 'U', 'A'), 2700);
    });

    test('otro lado desconocido: solo mueve su cuenta en el sentido de transferIncoming', () {
      final inc = mv(MovementKind.transfer, 400, account: 'B', incoming: true);
      final out = mv(MovementKind.transfer, 400, account: 'B');
      expect(accountEffectMinor(inc, 'B', 'A'), 400);
      expect(accountEffectMinor(out, 'B', 'A'), -400);
      expect(accountEffectMinor(inc, 'A', 'A'), 0);
      expect(accountEffectMinor(out, 'A', 'A'), 0);
    });

    test('otro lado desconocido sin accountId es de la cuenta por defecto', () {
      expect(accountEffectMinor(mv(MovementKind.transfer, 400, incoming: true), 'A', 'A'), 400);
      expect(accountEffectMinor(mv(MovementKind.transfer, 400, incoming: true), 'B', 'A'), 0);
    });
  });

  group('computeBalances', () {
    test('saldo = saldo inicial + efecto de sus movimientos', () {
      final balances = computeBalances(
        [acc('A', isDefault: true, initial: 1000), acc('B', initial: 50)],
        [mv(MovementKind.income, 500), mv(MovementKind.expense, 200, account: 'B')],
      );
      expect(balances, {'A': 1500, 'B': -150});
    });

    test('transferencia de 10000 de A a B: A −10000, B +10000', () {
      expect(computeBalances([a, b], [makeTransfer(from: a, to: b, amountMinor: 10000, date: _day)]),
          {'A': -10000, 'B': 10000});
    });

    test('entre monedas con receivedMinor', () {
      final t = makeTransfer(from: a, to: usd, amountMinor: 10000, receivedMinor: 2700, date: _day);
      expect(computeBalances([a, usd], [t]), {'A': -10000, 'U': 2700});
    });

    test('una cuenta solo cuenta movimientos en su moneda', () {
      final balances = computeBalances([a, usd], [
        mv(MovementKind.expense, 1500, currency: 'USD'),
        mv(MovementKind.expense, 700, currency: 'USD', account: 'U'),
        mv(MovementKind.expense, 300, currency: 'PEN', account: 'U'),
      ]);
      expect(balances, {'A': 0, 'U': -700});
    });

    test('otro lado desconocido en moneda ajena: solo cuenta si entra con receivedMinor', () {
      final balances = computeBalances([a, usd], [
        mv(MovementKind.transfer, 1000, currency: 'USD', account: 'A', incoming: true),
        mv(MovementKind.transfer, 1000, currency: 'USD', account: 'A'),
        mv(MovementKind.transfer, 100, currency: 'USD', account: 'A', incoming: true, received: 370),
      ]);
      expect(balances['A'], 370);
    });

    test('sin cuentas no hay saldos', () {
      expect(computeBalances(const [], [mv(MovementKind.expense, 1)]), isEmpty);
    });

    test('si ninguna está marcada, la primera hace de cuenta por defecto', () {
      expect(computeBalances([b, acc('C')], [mv(MovementKind.expense, 5)]), {'B': -5, 'C': 0});
    });

    test('un gasto de 2500 con paidMinor 10000 baja la cuenta 10000', () {
      expect(computeBalances([a], [mv(MovementKind.expense, 2500, paid: 10000)]), {'A': -10000});
    });

    test('una suscripción no cambia el saldo', () {
      expect(computeBalances([a], [mv(MovementKind.expense, 2990, origin: MovementOrigin.subscription)]), {'A': 0});
    });

    test('un cobro saldado (settlement) mueve la cuenta', () {
      expect(computeBalances([a], [mv(MovementKind.income, 2500, origin: MovementOrigin.settlement)]), {'A': 2500});
    });
  });

  group('initialMinor es el saldo en initialDate', () {
    final start = DateTime(2026, 10, 15, 12);
    final opened = acc('A', isDefault: true, initial: 100000).copyWith(initialDate: start);

    test('un gasto anterior no cambia el saldo', () {
      final older = mv(MovementKind.expense, 5000, date: start.subtract(const Duration(seconds: 1)));
      expect(computeBalances([opened], [older]), {'A': 100000});
    });

    test('una fila justo en initialDate cuenta', () {
      expect(computeBalances([opened], [mv(MovementKind.expense, 5000, date: start)]), {'A': 95000});
    });

    test('se comparan instantes, no días: el mismo día pero antes no cuenta', () {
      final morning = mv(MovementKind.expense, 5000, date: DateTime(2026, 10, 15, 8));
      final evening = mv(MovementKind.expense, 700, date: DateTime(2026, 10, 15, 20));
      expect(computeBalances([opened], [morning, evening]), {'A': 99300});
    });

    test('una transferencia entre los dos initialDate solo mueve el lado que corresponde', () {
      final early = acc('B').copyWith(initialDate: DateTime(2026, 10, 1));
      final late = acc('C').copyWith(initialDate: DateTime(2026, 10, 20));
      final between = DateTime(2026, 10, 10);
      final outOfEarly = mv(MovementKind.transfer, 400, account: 'B', to: 'C', date: between);
      final outOfLate = mv(MovementKind.transfer, 900, account: 'C', to: 'B', date: between);
      expect(computeBalances([early, late], [outOfEarly]), {'B': -400, 'C': 0});
      expect(computeBalances([early, late], [outOfLate]), {'B': 900, 'C': 0});
    });

    test('la cuenta migrada conserva las filas antiguas', () {
      final migrated = newDefaultAccount('PEN');
      expect(migrated.initialDate, DateTime.fromMillisecondsSinceEpoch(0));
      expect(
        computeBalances([migrated], [mv(MovementKind.income, 100000, date: DateTime(2020, 1, 1))]),
        {migrated.id: 100000},
      );
    });
  });

  group('un ajuste es un punto de control', () {
    final today = DateTime(2026, 10, 20, 9);
    final lastMonth = DateTime(2026, 9, 20);
    final later = today.add(const Duration(hours: 1));
    final start = acc('A', isDefault: true, initial: 5000).copyWith(initialDate: DateTime(2026, 1, 1));
    final adjust = makeAdjustment(account: start, currentMinor: 5000, realMinor: 4200, now: today)!;

    test('un gasto de antes apuntado después ya estaba en el saldo real', () {
      final backdated = mv(MovementKind.expense, 1000, date: lastMonth, createdAt: later);
      expect(computeBalances([start], [adjust, backdated]), {'A': 4200});
    });

    test('un gasto posterior al ajuste lo mueve', () {
      final after = mv(MovementKind.expense, 1000, date: later, createdAt: later);
      expect(computeBalances([start], [adjust, after]), {'A': 3200});
    });

    test('un gasto de antes apuntado antes sigue contando: la diferencia ya lo tiene en cuenta', () {
      final known = mv(MovementKind.expense, 1000, date: lastMonth, createdAt: lastMonth);
      final current = computeBalances([start], [known])['A']!;
      expect(current, 4000);
      final fix = makeAdjustment(account: start, currentMinor: current, realMinor: 4200, now: today)!;
      expect(fix.adjustmentMinor, 200);
      expect(computeBalances([start], [known, fix]), {'A': 4200});
    });

    test('los ajustes siempre cuentan, también uno anterior apuntado después', () {
      final older = mv(
        MovementKind.adjustment,
        300,
        account: 'A',
        adjustment: -300,
        date: lastMonth,
        createdAt: later,
      );
      expect(computeBalances([start], [adjust, older]), {'A': 3900});
    });

    test('por cuenta: un ajuste en otra cuenta no frena este movimiento', () {
      final other = acc('B');
      final elsewhere = makeAdjustment(account: other, currentMinor: 0, realMinor: 50, now: today)!;
      final backdated = mv(MovementKind.expense, 1000, date: lastMonth, createdAt: later);
      expect(computeBalances([start, other], [elsewhere, backdated]), {'A': 4000, 'B': 50});
    });

    test('una transferencia atrasada solo frena el lado con ajuste', () {
      final other = acc('B').copyWith(initialDate: DateTime(2026, 1, 1));
      final t = mv(MovementKind.transfer, 1000, account: 'A', to: 'B', date: lastMonth, createdAt: later);
      expect(computeBalances([start, other], [adjust, t]), {'A': 4200, 'B': 1000});
    });

    test('con varios ajustes basta uno posterior ya registrado', () {
      final second = makeAdjustment(account: start, currentMinor: 4200, realMinor: 4000, now: later)!;
      final between = today.add(const Duration(minutes: 30));
      final m = mv(MovementKind.expense, 1000, date: between, createdAt: later.add(const Duration(hours: 1)));
      final notYet = mv(MovementKind.expense, 10, date: between, createdAt: between);
      expect(computeBalances([start], [adjust, second, m]), {'A': 4000});
      expect(computeBalances([start], [adjust, second, notYet]), {'A': 3990},
          reason: 'apuntado antes del segundo ajuste, tras la fecha del primero');
    });

    test('una transferencia atrasada hecha con makeTransfer se registra como apuntada ahora', () {
      final other = acc('B');
      final old = DateTime(2000, 1, 1);
      final t = makeTransfer(from: start, to: other, amountMinor: 100, date: old);
      expect(t.date, old);
      expect(t.createdAt.isAfter(old), isTrue);
    });
  });

  test('totalsByCurrency agrupa por moneda y deja fuera las archivadas', () {
    final accounts = [a, b, usd, acc('Z', archived: true)];
    expect(totalsByCurrency(accounts, {'A': 100, 'B': 50, 'U': 7, 'Z': 9999}), {'PEN': 150, 'USD': 7});
  });

  group('makeAdjustment', () {
    final now = DateTime(2026, 10, 20, 9);

    test('saldo 5000, real 4200 → adjustmentMinor −800', () {
      final m = makeAdjustment(account: a, currentMinor: 5000, realMinor: 4200, now: now)!;
      expect(m.kind, MovementKind.adjustment);
      expect(m.adjustmentMinor, -800);
      expect(m.amount, const Money(800, 'PEN'));
      expect(m.accountId, 'A');
      expect(m.title, 'Ajuste de saldo');
      expect(m.date, now);
      expect(m.createdAt, now);
      expect(computeBalances([acc('A', isDefault: true, initial: 5000)], [m]), {'A': 4200});
    });

    test('hacia arriba y con ids distintos', () {
      final x = makeAdjustment(account: a, currentMinor: 100, realMinor: 350, now: now)!;
      final y = makeAdjustment(account: a, currentMinor: 100, realMinor: 350, now: now)!;
      expect(x.adjustmentMinor, 250);
      expect(x.id, isNot(y.id));
    });

    test('real = actual → null', () {
      expect(makeAdjustment(account: a, currentMinor: 5000, realMinor: 5000, now: now), isNull);
    });
  });

  group('makeTransfer', () {
    test('lleva ambas cuentas, título y nota', () {
      final bcp = acc('bcp', isDefault: true).copyWith(name: 'BCP');
      final dale = acc('dale').copyWith(name: 'Dale');
      final m = makeTransfer(from: bcp, to: dale, amountMinor: 4000, date: _day, note: 'recarga');
      expect(m.kind, MovementKind.transfer);
      expect(m.accountId, 'bcp');
      expect(m.toAccountId, 'dale');
      expect(m.amount, const Money(4000, 'PEN'));
      expect(m.title, 'BCP → Dale');
      expect(m.note, 'recarga');
      expect(m.receivedMinor, isNull);
      expect(m.categoryId, kNoCategoryId);
    });

    test('entre monedas exige el importe recibido; a la misma cuenta no se puede', () {
      expect(() => makeTransfer(from: a, to: usd, amountMinor: 1, date: _day), throwsArgumentError);
      expect(() => makeTransfer(from: a, to: a, amountMinor: 1, date: _day), throwsArgumentError);
    });

    test('el importe tiene que ser positivo', () {
      expect(() => makeTransfer(from: a, to: b, amountMinor: 0, date: _day), throwsArgumentError);
      expect(() => makeTransfer(from: a, to: b, amountMinor: -1, date: _day), throwsArgumentError);
    });
  });

  group('los ayudantes de gastos no ven transferencias, ajustes ni saldados', () {
    final categories = defaultCategories();
    final others = [
      mv(MovementKind.transfer, 4000, account: 'A', to: 'B', title: 'Dale'),
      mv(MovementKind.adjustment, 4000, account: 'A', adjustment: 4000, title: 'Dale'),
      mv(MovementKind.expense, 4000, origin: MovementOrigin.settlement, title: 'Dale'),
    ];

    test('suggestCategory', () {
      expect(suggestCategory(merchant: 'Dale', history: others, categories: categories), isNull);
    });

    test('findMatchingPayments', () {
      expect(findMatchingPayments(movements: others, amountMinor: 4000, merchant: 'Dale', date: _day), isEmpty);
    });

    test('findRecentDuplicate no toma una transferencia ni un ajuste por el mismo gasto', () {
      expect(
        findRecentDuplicate(movements: others.take(2).toList(), amountMinor: 4000, merchant: 'Dale', now: _day),
        isNull,
      );
    });
  });

  group('MemoryAccounts', () {
    test('ensureDefault dos veces deja una', () async {
      final repo = MemoryAccounts();
      await Future.wait([repo.ensureDefault('PEN'), repo.ensureDefault('PEN')]);
      expect(repo.saved.single.name, 'Mi cuenta');
    });
  });

  group('HiveAccountRepository', () {
    late Directory dir;
    late LocalStore store;
    late HiveAccountRepository repo;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('outflow_accounts');
      Hive.init(dir.path);
      store = await LocalStore.openUnencrypted();
      repo = HiveAccountRepository(store);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      dir.deleteSync(recursive: true);
    });

    Future<List<WalletAccount>> all() => repo.watchAll().first;

    test('ensureDefault crea "Mi cuenta" con saldo inicial 0 en la moneda pedida', () async {
      final d = await repo.ensureDefault('USD');
      expect(d.name, 'Mi cuenta');
      expect(d.currency, 'USD');
      expect(d.initialMinor, 0);
      expect(d.initialDate, kAccountBeginning, reason: 'conserva todo el historial');
      expect(d.isDefault, isTrue);
      expect(d.archived, isFalse);
      expect((await all()).single.id, d.id);
    });

    test('ensureDefault dos veces, también a la vez, deja una', () async {
      final both = await Future.wait([repo.ensureDefault('PEN'), repo.ensureDefault('PEN')]);
      final third = await repo.ensureDefault('PEN');
      expect((await all()).length, 1);
      expect({both[0].id, both[1].id, third.id}.length, 1);
    });

    test('ensureDefault no crea nada si ya hay cuentas, y devuelve la por defecto', () async {
      await repo.save(acc('B'));
      await repo.save(acc('A', isDefault: true));
      final d = await repo.ensureDefault('USD');
      expect(d.id, 'A');
      expect((await all()).length, 2);
    });

    test('watchAll: la por defecto primero y re-emite al guardar', () async {
      await repo.save(acc('Z'));
      await repo.save(acc('Y', isDefault: true));
      await repo.save(acc('B'));
      expect((await all()).map((x) => x.id), ['Y', 'B', 'Z']);
      final next = repo.watchAll().skip(1).first;
      await pumpEventQueue();
      await repo.save(acc('C'));
      expect((await next).map((x) => x.id), ['Y', 'B', 'C', 'Z']);
    });

    test('borrar: sin movimientos se borra; con movimientos se archiva', () async {
      await repo.save(acc('A', isDefault: true));
      await repo.save(acc('libre'));
      await repo.save(acc('origen'));
      await repo.save(acc('destino'));
      final t = mv(MovementKind.transfer, 100, account: 'origen', to: 'destino');
      await store.write(LocalStore.movementsBox, t.id, t.toJson());

      await repo.delete('libre');
      await repo.delete('origen');
      await repo.delete('destino');

      final left = {for (final x in await all()) x.id: x};
      expect(left.containsKey('libre'), isFalse);
      expect(left['origen']!.archived, isTrue);
      expect(left['destino']!.archived, isTrue);
    });

    test('la cuenta por defecto no se borra ni se archiva', () async {
      await repo.save(acc('A', isDefault: true));
      await repo.delete('A');
      expect((await all()).single.archived, isFalse);
      await repo.save(acc('A', isDefault: true, archived: true));
      expect((await all()).single.archived, isFalse);
    });

    group('quien actualiza (Review Focus 1)', () {
      // Tal como los guardaba la versión anterior: sin ningún campo de cuentas.
      final oldDocs = <String, Map<String, Object?>>{
        'saldo': {
          'id': 'saldo',
          'kind': 'income',
          'amount': {'minor': 100000, 'currency': 'PEN'},
          'categoryId': 'income_other',
          'date': '2026-10-01T09:00:00.000',
          'title': 'Saldo inicial',
          'origin': 'initialBalance',
        },
        'almuerzo': {
          'id': 'almuerzo',
          'kind': 'expense',
          'amount': {'minor': 2000, 'currency': 'PEN'},
          'categoryId': 'food',
          'date': '2026-10-05T13:00:00.000',
          'origin': 'manual',
        },
        'sub:nf:2026-10-06': {
          'id': 'sub:nf:2026-10-06',
          'kind': 'expense',
          'amount': {'minor': 2990, 'currency': 'PEN'},
          'categoryId': 'subscriptions',
          'date': '2026-10-06T00:00:00.000',
          'origin': 'subscription',
          'subscriptionId': 'nf',
        },
      };
      final settings = WalletSettings(walletStartedAt: DateTime(2026, 10, 1), onboardingDone: true);

      String summary(List<Movement> ms) {
        final s = MonthSummary.compute(
          movements: ms,
          subscriptions: const [],
          settings: settings,
          month: DateTime(2026, 10),
          now: DateTime(2026, 10, 20),
        );
        return '${s.income.minor} ${s.expense.minor} ${s.carriedIn.minor} ${s.remaining.minor} '
            '${s.afterPending.minor} ${{for (final e in s.expenseByCategory.entries) e.key: e.value.minor}}';
      }

      // Con un oyente: sin ninguno, Riverpod deja el stream en pausa.
      Future<T> load<T>(ProviderContainer c, StreamProvider<T> provider) =>
          c.listen(provider.future, (_, _) {}).read();

      ProviderContainer container() {
        final c = ProviderContainer(overrides: [
          localStoreProvider.overrideWithValue(store),
          walletSettingsRepositoryProvider.overrideWithValue(MemorySettings(settings)),
        ]);
        addTearDown(c.dispose);
        return c;
      }

      test('nace una sola "Mi cuenta", el saldo cuadra y "Te queda" no cambia', () async {
        await store.writeAll(LocalStore.movementsBox, oldDocs);
        final before = store.readAll(LocalStore.movementsBox);
        final summaryBefore = summary(before.map(Movement.fromJson).toList());

        // Dos arranques a la vez y otro después.
        final c = container();
        await Future.wait([load(c, accountsProvider), load(container(), accountsProvider)]);
        await load(container(), accountsProvider);

        final accounts = store.readAll(LocalStore.accountsBox);
        expect(accounts.length, 1);
        expect(accounts.single['name'], 'Mi cuenta');
        expect(accounts.single['currency'], 'PEN');

        // Los movimientos ni se tocan.
        expect(store.readAll(LocalStore.movementsBox), before);
        expect(summary(store.readAll(LocalStore.movementsBox).map(Movement.fromJson).toList()), summaryBefore);

        c.listen(accountBalancesProvider, (_, _) {});
        await load(c, movementsProvider);
        await pumpEventQueue();
        final balances = c.read(accountBalancesProvider).value!;
        expect(balances.values.single, 100000 - 2000, reason: 'la suscripción no descuenta');
        expect(c.read(defaultAccountProvider)?.name, 'Mi cuenta');
      });

      test('la cuenta nace en la moneda principal del usuario', () async {
        final c = ProviderContainer(overrides: [
          localStoreProvider.overrideWithValue(store),
          walletSettingsRepositoryProvider.overrideWithValue(MemorySettings(const WalletSettings(currency: 'USD'))),
        ]);
        addTearDown(c.dispose);
        final accounts = await load(c, accountsProvider);
        expect(accounts.single.currency, 'USD');
      });

      test('mientras carga, los saldos no son 0: están cargando', () {
        final c = container();
        expect(c.read(accountBalancesProvider).isLoading, isTrue);
      });
    });
  });
}
