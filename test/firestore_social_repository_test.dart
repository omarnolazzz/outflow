import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/friends/data/firestore_social_repository.dart';
import 'package:outflow/features/friends/data/social_repository.dart';
import 'package:outflow/features/friends/domain/shared_expense.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreSocialRepository mine;
  late FirestoreSocialRepository anas;

  const meAccount = Account(uid: 'me', email: 'Gabriel@Mail.com', displayName: 'Gabriel Nolazco');
  const anaAccount = Account(uid: 'ana', email: 'ana@mail.com', displayName: 'Ana Ruiz', photoUrl: 'https://x/ana.png');

  setUp(() async {
    db = FakeFirebaseFirestore();
    mine = FirestoreSocialRepository(db, meAccount);
    anas = FirestoreSocialRepository(db, anaAccount);
    await mine.publishProfile(meAccount);
    await anas.publishProfile(anaAccount);
  });

  SharedExpense expense({String id = 'e1'}) {
    const me = Person(uid: 'me', name: 'Gabriel Nolazco', email: 'gabriel@mail.com');
    const ana = Person(uid: 'ana', name: 'Ana Ruiz', email: 'ana@mail.com');
    return SharedExpense(
      id: id,
      createdBy: 'me',
      paidBy: 'me',
      participants: const ['me', 'ana'],
      people: const {'me': me, 'ana': ana},
      title: 'Cena',
      date: DateTime(2026, 10, 20),
      currency: 'PEN',
      totalMinor: 10000,
      categoryId: 'food',
      mode: SplitMode.equal,
      shares: const {'me': 5000, 'ana': 5000},
      updatedAt: DateTime(2026, 10, 20),
    );
  }

  test('publishProfile guarda el correo en minúsculas y sin espacios', () async {
    final doc = await db.collection('users').doc('me').get();
    expect(doc.data()!['email'], 'gabriel@mail.com');
    expect(doc.data()!['name'], 'Gabriel Nolazco');
    expect(doc.data()!.containsKey('updatedAt'), isTrue);
  });

  test('publishProfile escribe el índice de correo (id = correo normalizado) → {uid}', () async {
    final idx = await db.collection('emailIndex').doc('gabriel@mail.com').get();
    expect(idx.exists, isTrue);
    expect(idx.data(), {'uid': 'me'});
  });

  test('addFriend resuelve por el índice de correo, no por el campo email de users', () async {
    // Un impostor con el correo de Ana en su perfil no la suplanta: manda el índice.
    await db.collection('users').doc('impostor').set({'name': 'Falsa', 'email': 'ana@mail.com'});
    expect(await mine.addFriend('ana@mail.com'), AddFriendResult.sent);
    final req = await db.collection('friendRequests').doc('me_ana').get();
    expect(req.data()!['toPerson']['name'], 'Ana Ruiz');
    expect(req.data()!['fromPerson'], {
      'uid': 'me',
      'name': 'Gabriel Nolazco',
      'email': 'gabriel@mail.com',
      'photoUrl': null,
    });
  });

  test('sin entrada en el índice → notOnOutflow (aunque haya un users con ese correo)', () async {
    await db.collection('users').doc('luis').set({'name': 'Luis', 'email': 'luis@mail.com'});
    expect(await mine.addFriend('luis@mail.com'), AddFriendResult.notOnOutflow);
    expect(await mine.addFriend('a/b@mail.com'), AddFriendResult.notOnOutflow);
  });

  test('fromPerson sale de tu cuenta aunque no hayas publicado el perfil', () async {
    final fresh = FakeFirebaseFirestore();
    final me = FirestoreSocialRepository(fresh, meAccount);
    await FirestoreSocialRepository(fresh, anaAccount).publishProfile(anaAccount);
    expect(await me.addFriend('ana@mail.com'), AddFriendResult.sent);
    final req = await fresh.collection('friendRequests').doc('me_ana').get();
    expect(req.data()!['fromPerson']['email'], 'gabriel@mail.com');
    expect(await me.addFriend('GABRIEL@mail.com '), AddFriendResult.self);
  });

  test('addFriend envía la solicitud y no la repite', () async {
    expect(await mine.addFriend(' ANA@Mail.com '), AddFriendResult.sent);
    final req = await db.collection('friendRequests').doc('me_ana').get();
    expect(req.exists, isTrue);
    expect(req.data()!['status'], 'pending');
    expect(req.data()!['from'], 'me');
    expect(req.data()!['to'], 'ana');

    expect(await mine.addFriend('ana@mail.com'), AddFriendResult.alreadySent);

    final outgoing = await mine.watchOutgoing().first;
    expect(outgoing.map((r) => r.to.uid), ['ana']);
    final incoming = await anas.watchIncoming().first;
    expect(incoming.map((r) => r.id), ['me_ana']);
    expect(incoming.single.from.name, 'Gabriel Nolazco');
  });

  // Sin red, Firestore no confirma nunca la escritura final: addFriend no la
  // espera (los streams ya la ven en la caché) y solo registra si falla.
  test('addFriend no espera ni propaga la escritura de la solicitud', () async {
    whenCalling(Invocation.method(#set, null))
        .on(db.collection('friendRequests').doc('me_ana'))
        .thenThrow(FirebaseException(plugin: 'firestore', message: 'sin red'));
    expect(await mine.addFriend('ana@mail.com'), AddFriendResult.sent);
  });

  test('addFriend no espera ni propaga la aceptación', () async {
    expect(await anas.addFriend('gabriel@mail.com'), AddFriendResult.sent);
    whenCalling(Invocation.method(#update, null))
        .on(db.collection('friendRequests').doc('ana_me'))
        .thenThrow(FirebaseException(plugin: 'firestore', message: 'sin red'));
    expect(await mine.addFriend('ana@mail.com'), AddFriendResult.accepted);
  });

  test('addFriend: correo desconocido y el tuyo', () async {
    expect(await mine.addFriend('nadie@mail.com'), AddFriendResult.notOnOutflow);
    expect(await mine.addFriend(' gabriel@MAIL.com'), AddFriendResult.self);
  });

  test('si Ana ya te invitó, addFriend la acepta y sois amigos', () async {
    expect(await anas.addFriend('gabriel@mail.com'), AddFriendResult.sent);
    expect(await mine.addFriend('ana@mail.com'), AddFriendResult.accepted);

    final req = await db.collection('friendRequests').doc('ana_me').get();
    expect(req.data()!['status'], 'accepted');
    expect((await db.collection('friendRequests').doc('me_ana').get()).exists, isFalse);

    expect((await mine.watchFriends().first).map((p) => p.uid), ['ana']);
    expect((await anas.watchFriends().first).map((p) => p.uid), ['me']);
    expect(await mine.watchIncoming().first, isEmpty);
    expect(await mine.addFriend('ana@mail.com'), AddFriendResult.alreadyFriends);
  });

  test('answer acepta o rechaza (borra) la solicitud', () async {
    await anas.addFriend('gabriel@mail.com');
    await mine.answer('ana_me', accept: false);
    expect((await db.collection('friendRequests').doc('ana_me').get()).exists, isFalse);
    expect(await mine.watchFriends().first, isEmpty);

    await anas.addFriend('gabriel@mail.com');
    await mine.answer('ana_me', accept: true);
    expect((await mine.watchFriends().first).single.name, 'Ana Ruiz');
  });

  test('watchExpenses solo emite a participantes y viene del servidor', () async {
    await mine.saveExpense(expense());
    final snap = await mine.watchExpenses().first;
    expect(snap.expenses.map((e) => e.id), ['e1']);
    expect(snap.fromCache, isFalse);
    expect((await anas.watchExpenses().first).expenses.single.title, 'Cena');

    final javi = FirestoreSocialRepository(db, const Account(uid: 'javi', email: 'javi@mail.com', displayName: 'Javi'));
    expect((await javi.watchExpenses().first).expenses, isEmpty);
  });

  test('settle cambia solo settled.<deudor>', () async {
    await mine.saveExpense(expense());
    final before = (await db.collection('expenses').doc('e1').get()).data()!;
    await anas.settle('e1', 'ana');
    final after = (await db.collection('expenses').doc('e1').get()).data()!;

    expect((after['settled'] as Map).keys, ['ana']);
    expect((after['settled'] as Map)['ana']['by'], 'ana');
    final changed = {
      for (final k in {...before.keys, ...after.keys})
        if (before[k].toString() != after[k].toString()) k,
    };
    expect(changed, {'settled', 'updatedAt'});

    final e = (await mine.watchExpenses().first).expenses.single;
    expect(e.isSettled('ana'), isTrue);
  });

  test('updateExpense no pisa un pago marcado mientras el creador editaba', () async {
    await mine.saveExpense(expense());
    final stale = expense(); // lo que el creador tenía al abrir el editor
    await anas.settle('e1', 'ana');
    await mine.updateExpense(stale.copyWith(title: 'Cena en Barranco', updatedAt: DateTime(2026, 10, 21)));

    final e = (await mine.watchExpenses().first).expenses.single;
    expect(e.title, 'Cena en Barranco');
    expect(e.updatedAt, DateTime(2026, 10, 21));
    expect(e.isSettled('ana'), isTrue);
  });

  test('updateExpense borra solo los pagos que el editor quitó', () async {
    await mine.saveExpense(expense().copyWith(
      participants: const ['me', 'ana', 'javi'],
      people: {...expense().people, 'javi': const Person(uid: 'javi', name: 'Javi', email: 'javi@mail.com')},
      shares: const {'me': 4000, 'ana': 3000, 'javi': 3000},
    ));
    await anas.settle('e1', 'ana');
    await mine.settle('e1', 'javi');
    final edited = (await mine.watchExpenses().first).expenses.single;
    await mine.updateExpense(
      edited.copyWith(totalMinor: 13000, shares: const {'me': 4000, 'ana': 6000, 'javi': 3000}),
      unsettle: const {'ana'},
    );

    final e = (await mine.watchExpenses().first).expenses.single;
    expect(e.totalMinor, 13000);
    expect(e.shareOf('ana'), 6000);
    expect(e.isSettled('ana'), isFalse);
    expect(e.isSettled('javi'), isTrue);
  });

  test('deleteExpense lo quita del stream', () async {
    await mine.saveExpense(expense());
    await mine.saveExpense(expense(id: 'e2'));
    await mine.deleteExpense('e1');
    expect((await mine.watchExpenses().first).expenses.map((e) => e.id), ['e2']);
  });

  test('UnavailableSocialRepository: no disponible, vacío y no escribe', () async {
    const repo = UnavailableSocialRepository();
    expect(repo.available, isFalse);
    expect(await repo.watchFriends().first, isEmpty);
    final snap = await repo.watchExpenses().first;
    expect(snap.expenses, isEmpty);
    expect(snap.fromCache, isTrue);
    expect(() => repo.addFriend('a@b.com'), throwsStateError);
    expect(() => repo.saveExpense(expense()), throwsStateError);
  });
}
