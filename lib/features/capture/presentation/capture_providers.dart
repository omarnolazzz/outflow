import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../account/presentation/session_controller.dart';
import '../../wallet/domain/movement.dart';
import '../../wallet/domain/wallet_account.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../data/capture_inbox.dart';
import '../data/capture_sources_repository.dart';
import '../domain/process_captures.dart';

/// Lo que espera confirmación, lo más reciente primero.
final reviewMovementsProvider = Provider<List<Movement>>((ref) {
  final movements = ref.watch(movementsProvider).value ?? const <Movement>[];
  return movements.where((m) => m.needsReview).toList()
    ..sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });
});

final captureRunnerProvider = Provider<CaptureRunner>(CaptureRunner.new);

/// Procesa la bandeja en `Ready` y al volver a primer plano (`_onReturn`
/// invalida `nowProvider`). Se observa en `app.dart`.
final captureSyncProvider = Provider<void>((ref) {
  final session = ref.watch(sessionControllerProvider);
  ref.watch(nowProvider);
  if (session is! Ready) return;
  final runner = ref.read(captureRunnerProvider);
  Future.microtask(runner.run);
});

/// Una sola pasada a la vez. Si piden otra mientras tanto, se hace al terminar.
class CaptureRunner {
  CaptureRunner(this._ref);
  final Ref _ref;

  Future<void>? _running;
  bool _again = false;

  Future<void> run() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      try {
        await _once();
      } catch (e) {
        // Solo el tipo: el error podría citar texto del banco. La bandeja sigue
        // ahí y se reintenta en la siguiente pasada.
        debugPrint('No se pudo procesar la bandeja de captura: ${e.runtimeType}');
      }
    } while (_again);
  }

  /// La wallet es de su dueña: otra sesión o bloqueada no la toca.
  bool get _ownerReady {
    final session = _ref.read(sessionControllerProvider);
    if (session is! Ready) return false;
    return _ref.read(walletSettingsRepositoryProvider).read().ownerUid == session.account.uid;
  }

  Future<void> _once() async {
    if (!_ownerReady) return;
    final inbox = _ref.read(captureInboxProvider);
    final events = await inbox.pending();
    if (events.isEmpty) {
      // Quizá solo había líneas ilegibles.
      await inbox.commit();
      return;
    }

    final settings = _ref.read(walletSettingsRepositoryProvider).read();
    final accountRepo = _ref.read(accountRepositoryProvider);
    await accountRepo.ensureDefault(settings.currency);
    final accounts = await accountRepo.watchAll().first;
    final defaultAccount = defaultAccountOf(accounts);
    final movementRepo = _ref.read(movementRepositoryProvider);
    final movements = await movementRepo.watchAll().first;
    final categories = await _ref.read(categoryRepositoryProvider).watchAll().first;
    if (defaultAccount == null) return;

    final outcome = processCaptures(
      events: events,
      accounts: accounts,
      movements: movements,
      sourceAccounts: _ref.read(captureSourcesRepositoryProvider).read(),
      categories: categories,
      defaultAccountId: defaultAccount.id,
      now: _ref.read(nowProvider),
    );
    // Si mientras tanto se borró todo o se cerró la sesión, no se escribe nada.
    if (!_ownerReady) return;
    if (outcome.upsert.isNotEmpty) await movementRepo.saveAll(outcome.upsert);
    // Solo ahora: un corte antes deja los eventos, y reprocesar no duplica.
    await inbox.commit();
  }
}
