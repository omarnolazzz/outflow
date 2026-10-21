import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/domain/money.dart';
import '../../wallet/data/hive_movement_repository.dart';
import '../../wallet/data/wallet_settings_repository.dart';
import '../../wallet/domain/default_categories.dart';
import '../../wallet/domain/movement.dart';

enum OnboardingStep { currency, startingBalance, carryOver, subscriptions, notifications, faceId, done }

/// Estado del asistente de configuración inicial. El corto (para quien ya
/// tenía datos) salta las suscripciones y los avisos.
class OnboardingController extends ChangeNotifier {
  OnboardingController({
    required this.short,
    required WalletSettingsRepository settings,
    required this.movements,
  }) : _settings = settings {
    final s = settings.read();
    _currency = s.currency;
    _carryOver = s.carryOver;
    _faceId = s.faceIdEnabled;
  }

  final bool short;
  final WalletSettingsRepository _settings;
  final MovementRepository movements;

  late final List<OnboardingStep> steps = short
      ? const [
          OnboardingStep.currency,
          OnboardingStep.startingBalance,
          OnboardingStep.carryOver,
          OnboardingStep.faceId,
          OnboardingStep.done,
        ]
      : OnboardingStep.values;

  int _index = 0;
  int get index => _index;
  OnboardingStep get step => steps[_index];

  /// 0–1 para la barra de progreso.
  double get progress => (_index + 1) / steps.length;

  /// Dirección del último cambio de paso (para animar entrada/salida).
  bool forward = true;

  late String _currency;
  String get currency => _currency;
  int _startingBalanceMinor = 0;
  int get startingBalanceMinor => _startingBalanceMinor;
  late bool _carryOver;
  bool get carryOver => _carryOver;
  late bool _faceId;
  bool get faceId => _faceId;

  void next() {
    if (_index >= steps.length - 1) return;
    _index++;
    forward = true;
    notifyListeners();
  }

  void back() {
    if (_index == 0) return;
    _index--;
    forward = false;
    notifyListeners();
  }

  void setCurrency(String c) {
    _currency = c;
    notifyListeners();
  }

  void setStartingBalance(int minor) {
    _startingBalanceMinor = minor;
    notifyListeners();
  }

  void setCarryOver(bool v) {
    _carryOver = v;
    notifyListeners();
  }

  void setFaceId(bool v) {
    _faceId = v;
    notifyListeners();
  }

  /// Guarda todo. Un `walletStartedAt` previo se conserva.
  Future<void> complete(DateTime now) async {
    final s = _settings.read();
    await _settings.save(s.copyWith(
      currency: _currency,
      carryOver: _carryOver,
      faceIdEnabled: _faceId,
      onboardingDone: true,
      walletStartedAt: s.walletStartedAt ?? now,
    ));
    if (_startingBalanceMinor > 0) {
      await movements.save(Movement(
        id: const Uuid().v4(),
        kind: MovementKind.income,
        amount: Money(_startingBalanceMinor, _currency),
        categoryId: kOtherIncomeCategoryId,
        date: now,
        title: 'Saldo inicial',
        origin: MovementOrigin.initialBalance,
        createdAt: now,
      ));
    }
  }
}
