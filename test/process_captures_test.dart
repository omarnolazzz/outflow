import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/core/storage/local_store.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/capture/data/capture_inbox.dart';
import 'package:outflow/features/capture/data/capture_sources_repository.dart';
import 'package:outflow/features/capture/domain/process_captures.dart';
import 'package:outflow/features/capture/presentation/capture_providers.dart';
import 'package:outflow/features/wallet/data/hive_movement_repository.dart';
import 'package:outflow/features/wallet/domain/account_balances.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'parse_bank_text_test.dart' show kLemonMail;
import 'support/fakes.dart';

WalletAccount acc(String id, String name, {String? digits, String currency = 'PEN', bool isDefault = false, bool archived = false}) =>
    WalletAccount(
      id: id,
      name: name,
      type: AccountType.bank,
      currency: currency,
      initialMinor: 0,
      initialDate: kAccountBeginning,
      lastDigits: digits,
      isDefault: isDefault,
      archived: archived,
    );

final scotia = acc('scotia', 'Scotiabank', digits: '1234', isDefault: true);
final dale = acc('dale', 'Dale', digits: '5678');
final bcp = acc('bcp', 'BCP', digits: '9012');
final t0 = DateTime(2026, 11, 3, 10);
final now = DateTime(2026, 11, 3, 12);

CaptureEvent ev(String text, {String source = 'com.banco', DateTime? at, String? imageOp}) => CaptureEvent(
      sourceKey: source,
      sourceLabel: source,
      text: text,
      receivedAt: at ?? t0,
      imageOperationId: imageOp,
    );

CaptureOutcome run(
  List<CaptureEvent> events, {
  List<Movement> movements = const [],
  Map<String, String> sources = const {'com.banco': 'scotia', 'soporte@lemon.me': 'dale'},
  List<WalletAccount>? accounts,
}) =>
    processCaptures(
      events: events,
      accounts: accounts ?? [scotia, dale, bcp],
      movements: movements,
      sourceAccounts: sources,
      categories: defaultCategories(),
      defaultAccountId: 'scotia',
      now: now,
    );

/// Procesa y aplica el resultado sobre [movements], como la sincronización.
List<Movement> apply(List<Movement> movements, CaptureOutcome o) {
  final byId = {for (final m in movements) m.id: m};
  for (final m in o.upsert) {
    byId[m.id] = m;
  }
  return byId.values.toList();
}

Movement manual(String id, int minor, {String title = '', String account = 'scotia', DateTime? date, MovementKind kind = MovementKind.expense}) =>
    Movement(
      id: id,
      kind: kind,
      amount: Money(minor, 'PEN'),
      categoryId: kind == MovementKind.expense ? 'food' : 'salary',
      date: date ?? t0,
      createdAt: date ?? t0,
      title: title,
      accountId: account,
    );

void main() {
  group('un movimiento nuevo', () {
    test('sale marcado por revisar, con su origen, referencia y fecha de recepción', () {
      final o = run([ev(kLemonMail, source: 'soporte@lemon.me')]);
      final m = o.upsert.single;
      expect(m.kind, MovementKind.expense);
      expect(m.amount, const Money(400, 'PEN'));
      expect(m.title, 'Ana Torres Vega');
      expect(m.origin, MovementOrigin.capture);
      expect(m.needsReview, isTrue);
      expect(m.externalRef, '3f2a9c10-7b1d-4e55-9a01-0c1d2e3f4a5b');
      expect(m.accountId, 'dale');
      expect(m.date, t0);
      expect(m.createdAt, now);
      expect(m.note, '');
      expect(o.unmatchedSources, isEmpty);
    });

    test('un ingreso lleva categoría de ingreso', () {
      final m = run([ev('Recibiste S/ 50.00 de Ana')]).upsert.single;
      expect(m.kind, MovementKind.income);
      expect(m.categoryId, kOtherIncomeCategoryId);
      expect(run([ev('Yape: Ana te envió S/ 50.00')]).upsert.single.categoryId, 'transfer_in');
    });

    test('la categoría se sugiere por el comercio y si no, Otros', () {
      expect(run([ev('Pagaste S/ 5.00 en Tambo')]).upsert.single.categoryId, 'groceries');
      expect(run([ev('Pagaste S/ 5.00 en Zzz')]).upsert.single.categoryId, 'expense_other');
    });

    test('la fecha del texto gana a la de recepción si es otro día; el mismo día conserva la hora', () {
      expect(run([ev('Pagaste S/ 5.00 el 01/11/2026')]).upsert.single.date, DateTime(2026, 11, 1));
      expect(run([ev('Pagaste S/ 5.00 el 03/11/2026')]).upsert.single.date, t0);
    });

    test('sin importe no crea nada', () {
      final o = run([ev('Hola, tu saldo disponible es S/ 900.00')]);
      expect(o.upsert, isEmpty);
    });

    test('el número de operación de la imagen vale si el texto no trae', () {
      expect(run([ev('Pagaste S/ 5.00', imageOp: 'IMG-99')]).upsert.single.externalRef, 'IMG-99');
    });

    test('un importe sin moneda toma la de la cuenta que resulta', () {
      final usd = acc('usd', 'Dólares', currency: 'USD');
      final o = run([ev('Operación exitosa. Monto: 45.00', source: 'com.usd')], accounts: [scotia, usd], sources: {'com.usd': 'usd'});
      expect(o.upsert.single.amount, const Money(4500, 'USD'));
    });
  });

  group('cuenta', () {
    test('los últimos dígitos ganan a la fuente', () {
      final m = run([ev('Pagaste S/ 5.00 con tu tarjeta ****5678')]).upsert.single;
      expect(m.accountId, 'dale');
    });

    test('el nombre en el texto gana a la fuente', () {
      final m = run([ev('Pagaste S/ 5.00 en Tambo con tu cuenta BCP')]).upsert.single;
      expect(m.accountId, 'bcp');
    });

    test('la entidad y el nombre del destinatario no son tu cuenta', () {
      final m = run([ev(kLemonMail, source: 'soporte@lemon.me')]).upsert.single;
      expect(m.accountId, 'dale', reason: '"Entidad: BCP" es el banco del destinatario');
    });

    test('dos cuentas nombradas no deciden: gana la fuente', () {
      final m = run([ev('Pagaste S/ 5.00 con tu cuenta BCP y tu cuenta Dale')]).upsert.single;
      expect(m.accountId, 'scotia');
    });

    test('un nombre fuera de contexto de cuenta propia no cambia la cuenta de la fuente', () {
      for (final t in const [
        'Enviaste S/ 5.00 a Ana. Entidad destino: BCP',
        'Enviaste S/ 5.00 a Ana (BCP)',
        'Enviaste S/ 5.00 a Ana, banco BCP',
        'Pagaste S/ 5.00 en BCP',
        'Pagaste S/ 5.00 en Tambo. Atención en oficinas BCP',
        'BCP: pagaste S/ 5.00 en Tambo',
      ]) {
        final m = run([ev(t, source: 'soporte@lemon.me')]).upsert.single;
        expect(m.accountId, 'dale', reason: t);
        expect(m.kind, MovementKind.expense, reason: t);
      }
    });

    test('"Dale clic" no es la cuenta Dale', () {
      final m = run([ev('Pagaste S/ 5.00 en Tambo. Dale clic para ver el detalle')]).upsert.single;
      expect(m.accountId, 'scotia');
    });

    test('el nombre sí cuenta como cuenta propia', () {
      for (final t in const [
        'Pagaste S/ 5.00 desde tu cuenta BCP',
        'Pagaste S/ 5.00 con tu cuenta BCP',
        'Tu cuenta BCP: pagaste S/ 5.00',
        'Pagaste S/ 5.00 con tarjeta BCP',
      ]) {
        expect(run([ev(t, source: 'soporte@lemon.me')]).upsert.single.accountId, 'bcp', reason: t);
      }
    });

    test('sin nada más, la por defecto, y la fuente queda sin asignar', () {
      final e = ev('Pagaste S/ 5.00', source: 'com.nueva');
      final o = run([e]);
      expect(o.upsert.single.accountId, 'scotia');
      expect(o.unmatchedSources, [e]);
    });

    test('una fuente asignada a una cuenta archivada va a la por defecto', () {
      final e = ev('Pagaste S/ 5.00', source: 'com.vieja');
      final o = run([e], accounts: [scotia, acc('vieja', 'Vieja', archived: true)], sources: {'com.vieja': 'vieja'});
      expect(o.upsert.single.accountId, 'scotia');
      expect(o.unmatchedSources, [e]);
    });

    test('los dígitos de una cuenta archivada no cuentan', () {
      final o = run(
        [ev('Pagaste S/ 5.00 con tu tarjeta ****7777')],
        accounts: [scotia, acc('vieja', 'Vieja', digits: '7777', archived: true)],
      );
      expect(o.upsert.single.accountId, 'scotia');
    });
  });

  group('duplicados', () {
    const refMail = 'Pagaste S/ 25.00 en Tambo. N° de operación: 12345678';
    const notice = 'Pagaste S/ 25.00 en Tambo';

    test('el mismo pago por dos vías (aviso y correo) es un movimiento', () {
      final o = run([
        ev(notice, source: 'com.banco'),
        ev(refMail, source: 'com.banco', at: t0.add(const Duration(minutes: 3))),
      ]);
      final m = o.upsert.single;
      expect(m.externalRef, '12345678', reason: 'el correo completa lo que el aviso no traía');
      expect(m.note, '');
    });

    test('también al revés: primero el correo y luego el aviso', () {
      final o = run([
        ev(refMail, source: 'com.banco'),
        ev(notice, source: 'com.banco', at: t0.add(const Duration(minutes: 3))),
      ]);
      expect(o.upsert.single.externalRef, '12345678');
    });

    test('el mismo pago en otra tanda completa el existente', () {
      final first = apply(const [], run([ev(notice)]));
      final second = run([ev(refMail, at: t0.add(const Duration(hours: 1)))], movements: first);
      expect(second.upsert.single.id, first.single.id);
      expect(second.upsert.single.externalRef, '12345678');
    });

    test('completa un gasto apuntado a mano sin tocar lo que el usuario escribió', () {
      final o = run([ev(refMail)], movements: [manual('m1', 2500, title: 'Tambo Larco').copyWith(categoryId: 'home')]);
      final m = o.upsert.single;
      expect(m.id, 'm1');
      expect(m.externalRef, '12345678');
      expect(m.title, 'Tambo Larco');
      expect(m.categoryId, 'home');
      expect(m.needsReview, isFalse, reason: 'ya estaba confirmado');
      expect(m.origin, MovementOrigin.manual);
    });

    test('el mismo externalRef en la misma cuenta es uno, aunque lo demás difiera', () {
      final o = run([
        ev('Pagaste S/ 25.00 en Tambo. Referencia: AB12'),
        ev('Pagaste S/ 26.00 en Otro. Referencia: ab12', at: t0.add(const Duration(days: 9))),
      ]);
      expect(o.upsert, hasLength(1));
    });

    test('el mismo externalRef en otra cuenta no es duplicado', () {
      final o = run([
        ev('Pagaste S/ 25.00 con tarjeta ****1234. Referencia: AB12'),
        ev('Pagaste S/ 25.00 con tarjeta ****5678. Referencia: AB12'),
      ]);
      expect(o.upsert, hasLength(2));
    });

    test('dos compras con la misma tarjeta no comparten referencia', () {
      final o = run([
        ev('Compraste S/ 25.00 en Tambo con tarjeta N° 1234'),
        ev('Compraste S/ 40.00 en Wong con tarjeta N° 1234', at: t0.add(const Duration(minutes: 5))),
      ]);
      expect(o.upsert, hasLength(2));
      expect(o.upsert.map((m) => m.externalRef), everyElement(isNull));
      expect(o.upsert.map((m) => m.amount.minor), [2500, 4000]);
    });

    test('dos cafés iguales con comercio distinto son dos', () {
      final o = run([ev('Pagaste S/ 8.00 en Starbucks'), ev('Pagaste S/ 8.00 en Juan Valdez', at: t0.add(const Duration(minutes: 5)))]);
      expect(o.upsert, hasLength(2));
      expect(o.upsert.map((m) => m.note), everyElement(''));
    });

    test('dos operaciones con referencias distintas son dos, sin dudas', () {
      final o = run([
        ev('Pagaste S/ 8.00 en Tambo. Referencia: AA11'),
        ev('Pagaste S/ 8.00 en Tambo. Referencia: BB22', at: t0.add(const Duration(minutes: 5))),
      ]);
      expect(o.upsert, hasLength(2));
      expect(o.upsert.map((m) => m.note), everyElement(''));
    });

    test('dos pagos iguales sin referencia: se crean los dos y el segundo avisa', () {
      final o = run([ev(notice), ev(notice, at: t0.add(const Duration(minutes: 40)))]);
      expect(o.upsert, hasLength(2));
      expect(o.upsert.first.note, '');
      expect(o.upsert.last.note, '¿duplicado?');
      expect(o.upsert.last.needsReview, isTrue);
    });

    test('un aviso sin referencia sobre un gasto a mano igual: se crea y avisa', () {
      final o = run([ev(notice)], movements: [manual('m1', 2500, title: 'Tambo')]);
      expect(o.upsert.single.note, '¿duplicado?');
    });

    test('un comercio vacío es compatible', () {
      final o = run([ev('Pagaste S/ 25.00')], movements: [manual('m1', 2500, title: 'Tambo')]);
      expect(o.upsert.single.note, '¿duplicado?');
    });

    test('un comercio contenido en el otro es compatible', () {
      final o = run([ev(refMail)], movements: [manual('m1', 2500, title: 'Tambo Larco')]);
      expect(o.upsert.single.id, 'm1');
    });

    test('un movimiento solo absorbe un evento: el tercero se crea y avisa', () {
      // Correo con referencia y aviso son el mismo pago; otro aviso igual es dinero nuevo.
      var all = apply(const [], run([ev(refMail)]));
      all = apply(all, run([ev(notice, at: t0.add(const Duration(minutes: 1)))], movements: all));
      expect(all, hasLength(1));
      all = apply(all, run([ev(notice, at: t0.add(const Duration(minutes: 30)))], movements: all));
      expect(all, hasLength(2));
      expect(all.last.note, '¿duplicado?');
    });

    test('un evento fundido no se procesa dos veces', () {
      final merged = ev(notice, at: t0.add(const Duration(minutes: 1)));
      var all = apply(const [], run([ev(refMail)]));
      all = apply(all, run([merged], movements: all));
      expect(run([merged], movements: all).upsert, isEmpty);
      // Tampoco el que completó a uno sin referencia.
      final mail = ev(refMail, at: t0.add(const Duration(minutes: 2)));
      var other = apply(const [], run([ev(notice)]));
      other = apply(other, run([mail], movements: other));
      expect(other, hasLength(1));
      expect(run([mail], movements: other).upsert, isEmpty);
    });

    test('dentro de ±2 días con comercio igual completa; fuera es otro movimiento', () {
      final near = run([ev(refMail)], movements: [manual('m1', 2500, title: 'Tambo', date: t0.subtract(const Duration(days: 2)))]);
      expect(near.upsert.single.id, 'm1');
      final far = run([ev(refMail)], movements: [manual('m1', 2500, title: 'Tambo', date: t0.subtract(const Duration(days: 3)))]);
      expect(far.upsert.single.id, isNot('m1'));
      expect(far.upsert.single.note, '');
    });

    test('otro día y sin comercio con el que comparar: con duda, se crea y avisa', () {
      final o = run([ev('Pagaste S/ 25.00. Referencia: AB12')], movements: [manual('m1', 2500, date: t0.subtract(const Duration(days: 1)))]);
      expect(o.upsert.single.id, isNot('m1'));
      expect(o.upsert.single.note, '¿duplicado?');
    });

    test('sentido distinto no es duplicado', () {
      final o = run([ev('Recibiste S/ 25.00 de Tambo. Referencia: AB12')], movements: [manual('m1', 2500, title: 'Tambo')]);
      expect(o.upsert.single.id, isNot('m1'));
      expect(o.upsert.single.note, '');
    });

    test('un cobro de suscripción no es el pago capturado', () {
      final charge = Movement(
        id: 'sub:nf:2026-11-03',
        kind: MovementKind.expense,
        amount: const Money(2500, 'PEN'),
        categoryId: 'subscriptions',
        date: t0,
        createdAt: t0,
        title: 'Tambo',
        origin: MovementOrigin.subscription,
        accountId: 'scotia',
      );
      expect(run([ev(refMail)], movements: [charge]).upsert.single.id, isNot(charge.id));
    });

    test('la recarga en otra cuenta y el gasto desde Dale con igual importe son dos', () {
      final o = run([
        ev('Scotiabank: enviaste S/ 4.00 a Pepe'),
        ev(kLemonMail, source: 'soporte@lemon.me', at: t0.add(const Duration(minutes: 1))),
      ]);
      expect(o.upsert, hasLength(2));
      expect(o.upsert.map((m) => m.accountId).toSet(), {'scotia', 'dale'});
      expect(o.upsert.map((m) => m.note), everyElement(''));
    });

    test('la recarga como transferencia a Dale tampoco es duplicado del gasto desde Dale', () {
      final o = run([
        ev('Scotiabank: transferiste S/ 4.00 a Dale'),
        ev(kLemonMail, source: 'soporte@lemon.me', at: t0.add(const Duration(minutes: 1))),
      ]);
      expect(o.upsert, hasLength(2));
      expect(o.upsert.first.kind, MovementKind.transfer);
      expect(o.upsert.last.kind, MovementKind.expense);
      expect(o.upsert.map((m) => m.note), everyElement(''));
    });

    test('una transferencia ya apuntada es el mismo dinero que entra en su destino', () {
      final t = makeTransfer(from: scotia, to: dale, amountMinor: 400, date: t0, now: t0);
      final o = run([ev('Recibiste S/ 4.00. Referencia: AB12 en tu cuenta ****5678')], movements: [t]);
      expect(o.upsert.single.id, t.id);
    });
  });

  group('transferencias', () {
    test('solo si reconoce un destino propio por nombre', () {
      final m = run([ev('Transferiste S/ 500.00 a BCP')]).upsert.single;
      expect(m.kind, MovementKind.transfer);
      expect(m.accountId, 'scotia');
      expect(m.toAccountId, 'bcp');
      expect(m.categoryId, kNoCategoryId);
      expect(m.title, 'Scotiabank → BCP');
      expect(m.origin, MovementOrigin.capture);
      expect(m.needsReview, isTrue);
    });

    test('por los dígitos del destino', () {
      final m = run([ev('Transferiste S/ 500.00 desde tu cuenta ****1234 a la cuenta ****5678')]).upsert.single;
      expect(m.kind, MovementKind.transfer);
      expect(m.accountId, 'scotia');
      expect(m.toAccountId, 'dale');
    });

    test('un destino ajeno es un gasto', () {
      final m = run([ev('Transferiste S/ 500.00 a Ana')]).upsert.single;
      expect(m.kind, MovementKind.expense);
      expect(m.toAccountId, isNull);
    });

    test('la cuenta origen no es su propio destino', () {
      final m = run([ev('Transferiste S/ 500.00 a Scotiabank')]).upsert.single;
      expect(m.kind, MovementKind.expense);
    });

    test('entre monedas distintas no se adivina lo recibido: gasto', () {
      final usd = acc('usd', 'Dólares', currency: 'USD');
      final m = run([ev('Transferiste S/ 500.00 a Dólares')], accounts: [scotia, usd]).upsert.single;
      expect(m.kind, MovementKind.expense);
    });

    test('recibido de una cuenta propia entra como transferencia', () {
      final m = run([ev('Transferencia recibida: S/ 50.00 de BCP')]).upsert.single;
      expect(m.kind, MovementKind.transfer);
      expect(m.accountId, 'bcp');
      expect(m.toAccountId, 'scotia');
    });

    test('una compra en un comercio con el nombre de una cuenta no es transferencia', () {
      final m = run([ev('Pagaste S/ 5.00 en BCP')]).upsert.single;
      expect(m.kind, MovementKind.expense);
    });

    test('convertir en transferencia conserva id, referencia y deja de estar por revisar', () {
      final m = run([ev('Pagaste S/ 5.00 en Dale. Referencia: AB12')]).upsert.single;
      final t = convertToTransfer(m, own: scotia, other: dale);
      expect(t.id, m.id);
      expect(t.kind, MovementKind.transfer);
      expect(t.accountId, 'scotia');
      expect(t.toAccountId, 'dale');
      expect(t.categoryId, kNoCategoryId);
      expect(t.externalRef, 'AB12');
      expect(t.needsReview, isFalse);
      expect(t.title, 'Scotiabank → Dale');

      final inc = run([ev('Recibiste S/ 5.00 de Pepe')]).upsert.single;
      final back = convertToTransfer(inc, own: scotia, other: dale);
      expect(back.accountId, 'dale');
      expect(back.toAccountId, 'scotia');
    });
  });

  group('procesar', () {
    test('procesar dos veces no duplica', () {
      final events = [ev('Pagaste S/ 8.00 en Starbucks'), ev('Pagaste S/ 8.00 en Starbucks', at: t0.add(const Duration(minutes: 9)))];
      final first = apply(const [], run(events));
      expect(first, hasLength(2));
      expect(run(events, movements: first).upsert, isEmpty);
    });

    test('el id sale del evento, así que sobrevive a guardar y leer la bandeja', () {
      final e = ev('Pagaste S/ 8.00');
      final back = CaptureEvent.fromJson(e.toJson());
      expect(captureMovementId(back), captureMovementId(e));
      expect(captureMovementId(e), startsWith('capture:'));
      expect(captureMovementId(ev('Pagaste S/ 8.01')), isNot(captureMovementId(e)));
      expect(run([e]).upsert.single.id, captureMovementId(e));
    });

    test('un evento ilegible no rompe los demás', () {
      final o = run([ev('@@@ %%% sin importe'), ev(''), ev('Pagaste S/ 5.00 en Tambo')]);
      expect(o.upsert.single.amount.minor, 500);
    });
  });

  group('bandeja', () {
    late Directory dir;
    late CaptureInbox inbox;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('outflow_inbox');
      inbox = CaptureInbox(directory: () async => dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('guarda en capture_inbox.jsonl y drain lo devuelve y borra', () async {
      await inbox.add(ev('uno'));
      await inbox.add(ev('dos\ncon salto'));
      expect(File('${dir.path}/capture_inbox.jsonl').existsSync(), isTrue);
      final events = await inbox.drain();
      expect(events.map((e) => e.text), ['uno', 'dos\ncon salto']);
      expect(dir.listSync(), isEmpty, reason: 'el texto no se queda en el teléfono');
      expect(await inbox.drain(), isEmpty);
    });

    test('una línea ilegible no pierde las demás', () async {
      await inbox.add(ev('uno'));
      File('${dir.path}/capture_inbox.jsonl').writeAsStringSync('{roto\n["x"]\n{"sourceKey":"a"}\n', mode: FileMode.append);
      await inbox.add(ev('dos'));
      expect((await inbox.drain()).map((e) => e.text), ['uno', 'dos']);
    });

    test('un carácter multibyte cortado solo pierde su línea', () async {
      await inbox.add(ev('uno'));
      final bad = [...utf8.encode('{"sourceKey":"a","text":"caf'), 0xC3, 0x0A];
      File('${dir.path}/capture_inbox.jsonl').writeAsBytesSync(bad, mode: FileMode.append);
      await inbox.add(ev('dós'));
      expect((await inbox.drain()).map((e) => e.text), ['uno', 'dós']);
    });

    test('tampoco bloquea al juntarse con lo que quedó de un corte', () async {
      await inbox.add(ev('uno'));
      await inbox.pending();
      File('${dir.path}/capture_inbox.jsonl').writeAsBytesSync([0xC3, 0x0A], mode: FileMode.append);
      await inbox.add(ev('dos'));
      expect((await inbox.drain()).map((e) => e.text), ['uno', 'dos']);
      expect(dir.listSync(), isEmpty);
    });

    test('hasta confirmar no se borra: tras un corte vuelve a leerlo', () async {
      await inbox.add(ev('uno'));
      expect((await inbox.pending()).single.text, 'uno');
      // Corte aquí: la app se reabre sin haber confirmado, con otro evento nuevo.
      const reopened = CaptureInbox.new;
      final again = reopened(directory: () async => dir);
      await again.add(ev('dos'));
      expect((await again.pending()).map((e) => e.text), ['uno', 'dos']);
      await again.commit();
      expect(dir.listSync(), isEmpty);
    });

    test('lo que llega mientras se procesa sobrevive a confirmar', () async {
      await inbox.add(ev('uno'));
      await inbox.pending();
      await inbox.add(ev('dos'));
      await inbox.commit();
      expect((await inbox.drain()).single.text, 'dos');
    });

    test('clear lo borra todo', () async {
      await inbox.add(ev('uno'));
      await inbox.pending();
      await inbox.add(ev('dos'));
      await inbox.clear();
      expect(dir.listSync(), isEmpty);
      expect(await inbox.drain(), isEmpty);
    });

    test('CaptureEvent ida y vuelta', () {
      final e = ev('texto', imageOp: 'IMG-1');
      final back = CaptureEvent.fromJson(e.toJson());
      expect(back.sourceKey, e.sourceKey);
      expect(back.sourceLabel, e.sourceLabel);
      expect(back.text, 'texto');
      expect(back.receivedAt, e.receivedAt);
      expect(back.imageOperationId, 'IMG-1');
    });
  });

  group('captureSyncProvider', () {
    late Directory dir;
    late LocalStore store;
    late CaptureInbox inbox;
    const owner = Account(uid: 'u1', email: 'x@example.com', displayName: 'Prueba');

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('outflow_capture_sync');
      Hive.init(dir.path);
      store = await LocalStore.openUnencrypted();
      await store.writeAll(LocalStore.categoriesBox, {for (final c in defaultCategories()) c.id: c.toJson()});
      inbox = CaptureInbox(directory: () async => dir);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      dir.deleteSync(recursive: true);
    });

    ProviderContainer container(SessionState session, {String? ownerUid = 'u1', MovementRepository? movements}) {
      final c = ProviderContainer(overrides: [
        localStoreProvider.overrideWithValue(store),
        captureInboxProvider.overrideWithValue(inbox),
        sessionControllerProvider.overrideWith(() => _FixedSession(session)),
        walletSettingsRepositoryProvider.overrideWithValue(MemorySettings(WalletSettings(ownerUid: ownerUid, onboardingDone: true))),
        if (movements != null) movementRepositoryProvider.overrideWithValue(movements),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<void> sync(ProviderContainer c) async {
      c.read(captureSyncProvider);
      await c.read(captureRunnerProvider).run();
    }

    List<Movement> saved() => store.readAll(LocalStore.movementsBox).map(Movement.fromJson).toList();

    test('en Ready procesa la bandeja, guarda y la vacía', () async {
      await inbox.add(ev('Pagaste S/ 5.00 en Tambo'));
      await sync(container(const Ready(owner)));
      final m = saved().single;
      expect(m.needsReview, isTrue);
      expect(m.amount.minor, 500);
      expect(await inbox.drain(), isEmpty);
    });

    test('usa las fuentes asignadas', () async {
      final c = container(const Ready(owner));
      await store.write(LocalStore.accountsBox, 'dale', dale.toJson());
      await c.read(captureSourcesRepositoryProvider).assign('soporte@lemon.me', 'dale');
      await inbox.add(ev(kLemonMail, source: 'soporte@lemon.me'));
      await sync(c);
      expect(saved().single.accountId, 'dale');
    });

    test('bloqueada no toca la bandeja', () async {
      await inbox.add(ev('Pagaste S/ 5.00'));
      await sync(container(const Locked(owner)));
      expect(saved(), isEmpty);
      expect((await inbox.drain()), hasLength(1));
    });

    test('otra cuenta distinta de la dueña no toca la bandeja', () async {
      await inbox.add(ev('Pagaste S/ 5.00'));
      await sync(container(const Ready(owner), ownerUid: 'otra'));
      expect(saved(), isEmpty);
      expect((await inbox.drain()), hasLength(1));
    });

    test('un corte al guardar no pierde eventos, y reprocesar no duplica', () async {
      await inbox.add(ev('Pagaste S/ 5.00'));
      await sync(container(const Ready(owner), movements: _FailingMovements(HiveMovementRepository(store))));
      expect(saved(), isEmpty);

      await sync(container(const Ready(owner)));
      expect(saved(), hasLength(1));
      expect(await inbox.drain(), isEmpty);
    });

    test('un corte tras guardar y antes de vaciar no duplica', () async {
      await inbox.add(ev('Pagaste S/ 5.00'));
      await sync(container(const Ready(owner)));
      // La bandeja reaparece igual, como si el borrado no hubiera llegado a hacerse.
      await inbox.add(ev('Pagaste S/ 5.00'));
      await sync(container(const Ready(owner)));
      expect(saved(), hasLength(1));
    });

    test('dos pasadas a la vez procesan una sola', () async {
      await inbox.add(ev('Pagaste S/ 5.00'));
      final c = container(const Ready(owner));
      final r = c.read(captureRunnerProvider);
      await Future.wait([r.run(), r.run(), r.run()]);
      expect(saved(), hasLength(1));
    });

    test('las fuentes se guardan en la caja de ajustes', () async {
      final repo = HiveCaptureSourcesRepository(store);
      expect(repo.read(), isEmpty);
      await repo.assign('com.banco', 'dale');
      await repo.assign('com.otro', 'bcp');
      expect(repo.read(), {'com.banco': 'dale', 'com.otro': 'bcp'});
      expect(HiveCaptureSourcesRepository(store).read()['com.banco'], 'dale');
      expect(store.read(LocalStore.settingsBox, 'capture.sources'), isNotNull);
    });
  });
}

class _FixedSession extends SessionController {
  _FixedSession(this._state);
  final SessionState _state;
  @override
  SessionState build() => _state;
}

class _FailingMovements implements MovementRepository {
  _FailingMovements(this._inner);
  final MovementRepository _inner;
  @override
  Stream<List<Movement>> watchAll() => _inner.watchAll();
  @override
  Future<void> save(Movement m) => _inner.save(m);
  @override
  Future<void> saveAll(Iterable<Movement> ms) => Future.error(StateError('Corte'));
  @override
  Future<void> delete(String id) => _inner.delete(id);
  @override
  Future<void> deleteAll(Iterable<String> ids) => _inner.deleteAll(ids);
}
