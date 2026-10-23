import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../account/domain/account.dart';
import '../domain/shared_expense.dart';
import '../domain/split_movements.dart';
import 'social_repository.dart';

/// Correo como se guarda y se busca: sin espacios y en minúsculas.
String normalizeEmail(String email) => email.trim().toLowerCase();

/// [SocialRepository] sobre Cloud Firestore.
///
/// Las consultas tienen la forma que exigen las reglas (`firestore.rules`):
/// solicitudes por `from == yo` o `to == yo` y gastos por
/// `participants arrayContains yo`. Los correos se buscan con `get` en
/// `emailIndex/{correo}` (no hay consultas sobre `users`).
class FirestoreSocialRepository implements SocialRepository {
  FirestoreSocialRepository(this._db, this._account, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final FirebaseFirestore _db;

  /// La cuenta con sesión: de ella sale tu copia en las solicitudes.
  final Account _account;
  final DateTime Function() _now;

  String get _myUid => _account.uid;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _emailIndex => _db.collection('emailIndex');
  CollectionReference<Map<String, dynamic>> get _requests => _db.collection('friendRequests');
  CollectionReference<Map<String, dynamic>> get _expenses => _db.collection('expenses');

  static const _pending = 'pending';
  static const _accepted = 'accepted';

  @override
  bool get available => true;

  /// Perfil e índice de correo juntos (las reglas exigen que el correo sea el
  /// de la cuenta con sesión).
  @override
  Future<void> publishProfile(Account me) {
    final email = normalizeEmail(me.email);
    final batch = _db.batch()
      ..set(_users.doc(me.uid), {
        'name': me.displayName,
        'email': email,
        'photoUrl': me.photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    if (_validDocId(email)) batch.set(_emailIndex.doc(email), {'uid': me.uid});
    return batch.commit();
  }

  /// Un id de documento no puede estar vacío ni contener '/'.
  static bool _validDocId(String id) => id.isNotEmpty && !id.contains('/');

  /// Tu copia en las solicitudes, sacada de la cuenta (no de la caché).
  Person get _mePerson => Person(
        uid: _myUid,
        name: _account.displayName,
        email: normalizeEmail(_account.email),
        photoUrl: _account.photoUrl,
      );

  // ---------------------------------------------------------------- Amigos

  /// Lee una solicitud; null si el documento está mal formado.
  FriendRequest? _request(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    if (data == null) return null;
    try {
      return FriendRequest(
        id: d.id,
        from: _person(data['from'], data['fromPerson']),
        to: _person(data['to'], data['toPerson']),
      );
    } catch (e) {
      debugPrint('Solicitud de amistad ilegible ${d.id}: $e');
      return null;
    }
  }

  static Person _person(Object? uid, Object? json) => json is Map
      ? Person.fromJson({...json.cast<String, Object?>(), 'uid': uid as String})
      : Person(uid: uid as String, name: '', email: '');

  /// Solicitudes enviadas y recibidas, con su estado.
  Stream<List<({FriendRequest request, String status})>> _all() => _combineLatest(
        _requests.where('from', isEqualTo: _myUid).snapshots(),
        _requests.where('to', isEqualTo: _myUid).snapshots(),
        (a, b) => [
          for (final d in [...a.docs, ...b.docs])
            if (_request(d) case final r?) (request: r, status: d.data()['status'] as String? ?? _pending),
        ],
      );

  @override
  Stream<List<Person>> watchFriends() => _all().map((all) {
        final byUid = <String, Person>{};
        for (final x in all) {
          if (x.status != _accepted) continue;
          final other = x.request.from.uid == _myUid ? x.request.to : x.request.from;
          byUid[other.uid] = other;
        }
        return byUid.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });

  @override
  Stream<List<FriendRequest>> watchIncoming() => _pendingWhere('to');

  @override
  Stream<List<FriendRequest>> watchOutgoing() => _pendingWhere('from');

  /// Solicitudes pendientes donde yo soy [field] (`from` o `to`).
  Stream<List<FriendRequest>> _pendingWhere(String field) =>
      _requests.where(field, isEqualTo: _myUid).snapshots().map((s) => [
            for (final d in s.docs)
              if ((d.data()['status'] ?? _pending) == _pending) ?_request(d),
          ]);

  @override
  Future<AddFriendResult> addFriend(String email) async {
    final wanted = normalizeEmail(email);
    final me = _mePerson;
    if (wanted == me.email) return AddFriendResult.self;
    if (!_validDocId(wanted)) return AddFriendResult.notOnOutflow;

    // Índice de correo y perfil, desde el servidor: una caché vieja no puede
    // decir que alguien no está.
    const server = GetOptions(source: Source.server);
    final DocumentSnapshot<Map<String, dynamic>> index;
    final DocumentSnapshot<Map<String, dynamic>> profile;
    try {
      index = await _emailIndex.doc(wanted).get(server);
      if (index.metadata.isFromCache) return AddFriendResult.offline;
      final uid = index.data()?['uid'];
      if (!index.exists || uid is! String || uid.isEmpty) return AddFriendResult.notOnOutflow;
      if (uid == _myUid) return AddFriendResult.self;
      profile = await _users.doc(uid).get(server);
      if (profile.metadata.isFromCache) return AddFriendResult.offline;
    } on FirebaseException catch (e) {
      debugPrint('Búsqueda de amigo sin servidor: $e');
      return AddFriendResult.offline;
    }
    final himUid = index.data()!['uid'] as String;
    final data = profile.data();
    // El correo es el del índice (validado por las reglas), no el del perfil.
    final him = data == null
        ? Person(uid: himUid, name: '', email: wanted)
        : Person(
            uid: himUid,
            name: data['name'] as String? ?? '',
            email: wanted,
            photoUrl: data['photoUrl'] as String?,
          );

    // Consultas en vez de `get` por id: las reglas no dejan leer un documento
    // que no existe (no hay `resource.data`), pero sí estas consultas.
    final mineToHim = await _requests.where('from', isEqualTo: _myUid).where('to', isEqualTo: himUid).get();
    final hisToMe = await _requests.where('from', isEqualTo: himUid).where('to', isEqualTo: _myUid).get();
    String? status(QuerySnapshot<Map<String, dynamic>> s) =>
        s.docs.isEmpty ? null : s.docs.first.data()['status'] as String? ?? _pending;

    if (status(mineToHim) == _accepted || status(hisToMe) == _accepted) return AddFriendResult.alreadyFriends;
    if (status(mineToHim) == _pending) return AddFriendResult.alreadySent;
    if (status(hisToMe) == _pending) {
      await _requests.doc(hisToMe.docs.first.id).update({'status': _accepted});
      return AddFriendResult.accepted;
    }

    await _requests.doc('${_myUid}_$himUid').set({
      'from': _myUid,
      'to': himUid,
      'fromPerson': me.toJson(),
      'toPerson': him.toJson(),
      'status': _pending,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return AddFriendResult.sent;
  }

  @override
  Future<void> answer(String requestId, {required bool accept}) => accept
      ? _requests.doc(requestId).update({'status': _accepted})
      : _requests.doc(requestId).delete();

  // ---------------------------------------------------------------- Gastos

  /// `fromCache` sale de los metadatos de Firestore: con
  /// `includeMetadataChanges` llega también el snapshot confirmado por el
  /// servidor. Solo ese autoriza a borrar movimientos de la wallet.
  @override
  Stream<ExpensesSnapshot> watchExpenses() => _expenses
          .where('participants', arrayContains: _myUid)
          .snapshots(includeMetadataChanges: true)
          .map((s) {
        final list = <SharedExpense>[];
        for (final d in s.docs) {
          try {
            list.add(SharedExpense.fromJson({...d.data(), 'id': d.id}));
          } catch (e) {
            debugPrint('Gasto compartido ilegible ${d.id}: $e');
          }
        }
        list.sort((a, b) => b.date.compareTo(a.date));
        return ExpensesSnapshot(list, fromCache: s.metadata.isFromCache);
      });

  @override
  Future<void> saveExpense(SharedExpense e) => _expenses.doc(e.id).set(e.toJson());

  @override
  Future<void> deleteExpense(String id) => _expenses.doc(id).delete();

  @override
  Future<void> settle(String expenseId, String debtorUid) {
    final at = _now().toIso8601String();
    return _expenses.doc(expenseId).update({
      'settled.$debtorUid': Settlement(by: _myUid, at: DateTime.parse(at)).toJson(),
      'updatedAt': at,
    });
  }
}

/// Emite `combine(a, b)` cada vez que cambia cualquiera, cuando ambos ya emitieron.
Stream<R> _combineLatest<A, B, R>(Stream<A> sa, Stream<B> sb, R Function(A, B) combine) {
  late StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  A? lastA;
  B? lastB;
  var hasA = false;
  var hasB = false;
  var done = 0;

  void emit() {
    if (hasA && hasB) controller.add(combine(lastA as A, lastB as B));
  }

  void onDone() {
    if (++done == 2) controller.close();
  }

  controller = StreamController<R>(
    onListen: () {
      subA = sa.listen((a) {
        lastA = a;
        hasA = true;
        emit();
      }, onError: controller.addError, onDone: onDone);
      subB = sb.listen((b) {
        lastB = b;
        hasB = true;
        emit();
      }, onError: controller.addError, onDone: onDone);
    },
    onPause: () {
      subA?.pause();
      subB?.pause();
    },
    onResume: () {
      subA?.resume();
      subB?.resume();
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}
