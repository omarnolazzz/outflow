import '../../account/domain/account.dart';
import '../domain/shared_expense.dart';
import '../domain/split_movements.dart';

/// Resultado de invitar a alguien por su correo.
enum AddFriendResult { sent, accepted, notOnOutflow, self, alreadyFriends, alreadySent, offline }

/// Solicitud de amistad pendiente (id `{from}_{to}`).
class FriendRequest {
  const FriendRequest({required this.id, required this.from, required this.to});

  final String id;
  final Person from;
  final Person to;
}

/// Perfiles, amigos y gastos compartidos en la nube.
abstract interface class SocialRepository {
  /// False sin Firebase o con la cuenta de vista previa.
  bool get available;

  /// Publica tu nombre, correo y foto para que te encuentren por correo.
  Future<void> publishProfile(Account me);

  Stream<List<Person>> watchFriends();
  Stream<List<FriendRequest>> watchIncoming();
  Stream<List<FriendRequest>> watchOutgoing();
  Future<AddFriendResult> addFriend(String email);

  /// Aceptar marca la solicitud como aceptada; rechazar la borra.
  Future<void> answer(String requestId, {required bool accept});

  Stream<ExpensesSnapshot> watchExpenses();

  /// Solo quien creó el gasto lo escribe entero.
  Future<void> saveExpense(SharedExpense e);

  /// El creador edita un gasto: escribe todo menos `settled`, para no pisar
  /// los pagos que otros marquen mientras tanto. Solo borra los pagos de
  /// [unsettle] (los que la edición invalidó).
  Future<void> updateExpense(SharedExpense e, {Set<String> unsettle = const {}});
  Future<void> deleteExpense(String id);

  /// Marca como pagada la parte de [debtorUid] (solo toca `settled.<uid>`).
  Future<void> settle(String expenseId, String debtorUid);
}

/// Sin Firebase (vista previa web, build sin configuración o cuenta simulada):
/// todo vacío y las escrituras fallan.
class UnavailableSocialRepository implements SocialRepository {
  const UnavailableSocialRepository();

  static Never _unavailable() => throw StateError('Amigos no está disponible sin una cuenta de Google.');

  @override
  bool get available => false;

  @override
  Future<void> publishProfile(Account me) async => _unavailable();

  @override
  Stream<List<Person>> watchFriends() => Stream.value(const []);

  @override
  Stream<List<FriendRequest>> watchIncoming() => Stream.value(const []);

  @override
  Stream<List<FriendRequest>> watchOutgoing() => Stream.value(const []);

  @override
  Future<AddFriendResult> addFriend(String email) async => _unavailable();

  @override
  Future<void> answer(String requestId, {required bool accept}) async => _unavailable();

  /// Como caché: nunca autoriza a borrar movimientos de la wallet.
  @override
  Stream<ExpensesSnapshot> watchExpenses() => Stream.value(const ExpensesSnapshot([], fromCache: true));

  @override
  Future<void> saveExpense(SharedExpense e) async => _unavailable();

  @override
  Future<void> updateExpense(SharedExpense e, {Set<String> unsettle = const {}}) async => _unavailable();

  @override
  Future<void> deleteExpense(String id) async => _unavailable();

  @override
  Future<void> settle(String expenseId, String debtorUid) async => _unavailable();
}
