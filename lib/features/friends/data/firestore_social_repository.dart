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
/// solicitudes por `from == yo` o `to == yo`, gastos por
/// `participants arrayContains yo` y búsqueda de correo con `limit(1)`.
class FirestoreSocialRepository implements SocialRepository {
  FirestoreSocialRepository(this._db, this._myUid, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final FirebaseFirestore _db;
  final String _myUid;
  final DateTime Function() _now;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _requests => _db.collection('friendRequests');
  CollectionReference<Map<String, dynamic>> get _expenses => _db.collection('expenses');

  static const _pending = 'pending';
  static const _accepted = 'accepted';

  @override
  bool get available => true;

  @override
  Future<void> publishProfile(Account me) => _users.doc(me.uid).set({
        'name': me.displayName,
        'email': normalizeEmail(me.email),
        'photoUrl': me.photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

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

  /// Mi perfil publicado (para la copia embebida en la solicitud).
  Future<Person> _me() async {
    try {
      final d = await _users.doc(_myUid).get();
      final data = d.data();
      if (data != null) return _person(_myUid, data);
    } catch (e) {
      debugPrint('No se pudo leer tu perfil: $e');
    }
    return Person(uid: _myUid, name: '', email: '');
  }

  @override
  Future<AddFriendResult> addFriend(String email) async {
    final wanted = normalizeEmail(email);
    final me = await _me();
    if (wanted.isEmpty) return AddFriendResult.notOnOutflow;
    if (wanted == me.email) return AddFriendResult.self;

    // Desde el servidor: una caché vieja no puede decir que alguien no está.
    final QuerySnapshot<Map<String, dynamic>> found;
    try {
      found = await _users.where('email', isEqualTo: wanted).limit(1).get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      debugPrint('Búsqueda de amigo sin servidor: $e');
      return AddFriendResult.offline;
    }
    if (found.metadata.isFromCache) return AddFriendResult.offline;
    if (found.docs.isEmpty) return AddFriendResult.notOnOutflow;
    final himDoc = found.docs.first;
    final himUid = himDoc.id;
    if (himUid == _myUid) return AddFriendResult.self;
    final him = _person(himUid, himDoc.data());

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
