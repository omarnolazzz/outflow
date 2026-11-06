import 'package:meta/meta.dart';

/// Ajustes de la wallet y de la configuración inicial.
@immutable
class WalletSettings {
  const WalletSettings({
    this.currency = 'PEN',
    this.carryOver = true,
    this.walletStartedAt,
    this.onboardingDone = false,
    this.faceIdEnabled = false,
    this.deletedChargeIds = const {},
    this.dismissedSplitMatchIds = const {},
    this.splitAccountIds = const {},
    this.ownerUid,
  });

  /// Moneda principal: la única que suma en la wallet.
  final String currency;

  /// Lo que sobra de un mes pasa al siguiente.
  final bool carryOver;

  /// Desde cuándo lleva la wallet (no se cuenta nada de meses anteriores).
  final DateTime? walletStartedAt;
  final bool onboardingDone;
  final bool faceIdEnabled;

  /// Cobros de suscripción que el usuario borró: no se vuelven a crear.
  final Set<String> deletedChargeIds;

  /// Gastos compartidos en los que el usuario ya respondió a "¿Es este
  /// pago?": no se vuelve a preguntar.
  final Set<String> dismissedSplitMatchIds;

  /// Cuenta de la que salió cada gasto compartido que pagaste tú (id del gasto
  /// → id de la cuenta). Solo en este teléfono: la wallet no sale de aquí.
  final Map<String, String> splitAccountIds;

  /// Cuenta de Google dueña de esta wallet: otra cuenta no la abre.
  final String? ownerUid;

  WalletSettings copyWith({
    String? currency,
    bool? carryOver,
    DateTime? walletStartedAt,
    bool? onboardingDone,
    bool? faceIdEnabled,
    Set<String>? deletedChargeIds,
    Set<String>? dismissedSplitMatchIds,
    Map<String, String>? splitAccountIds,
    String? ownerUid,
  }) =>
      WalletSettings(
        currency: currency ?? this.currency,
        carryOver: carryOver ?? this.carryOver,
        walletStartedAt: walletStartedAt ?? this.walletStartedAt,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        faceIdEnabled: faceIdEnabled ?? this.faceIdEnabled,
        deletedChargeIds: deletedChargeIds ?? this.deletedChargeIds,
        dismissedSplitMatchIds: dismissedSplitMatchIds ?? this.dismissedSplitMatchIds,
        splitAccountIds: splitAccountIds ?? this.splitAccountIds,
        ownerUid: ownerUid ?? this.ownerUid,
      );

  Map<String, Object?> toJson() => {
        'currency': currency,
        'carryOver': carryOver,
        'walletStartedAt': walletStartedAt?.toIso8601String(),
        'onboardingDone': onboardingDone,
        'faceIdEnabled': faceIdEnabled,
        'deletedChargeIds': (deletedChargeIds.toList()..sort()),
        'dismissedSplitMatchIds': (dismissedSplitMatchIds.toList()..sort()),
        'splitAccountIds': splitAccountIds,
        'ownerUid': ownerUid,
      };

  factory WalletSettings.fromJson(Map<String, Object?> json) {
    final started = json['walletStartedAt'] as String?;
    return WalletSettings(
      currency: json['currency'] as String? ?? 'PEN',
      carryOver: json['carryOver'] as bool? ?? true,
      walletStartedAt: started == null ? null : DateTime.parse(started),
      onboardingDone: json['onboardingDone'] as bool? ?? false,
      faceIdEnabled: json['faceIdEnabled'] as bool? ?? false,
      deletedChargeIds: {...?(json['deletedChargeIds'] as List?)?.cast<String>()},
      dismissedSplitMatchIds: {...?(json['dismissedSplitMatchIds'] as List?)?.cast<String>()},
      splitAccountIds: {...?(json['splitAccountIds'] as Map?)?.cast<String, String>()},
      ownerUid: json['ownerUid'] as String?,
    );
  }
}
