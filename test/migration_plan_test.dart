import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/cloud/domain/migration_plan.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';

/// Lo que deja una instalación nueva: "Mi cuenta" sin saldo y las categorías.
WalletDocs _fresh({Map<String, Map<String, Object?>> settings = const {}}) => {
      'accounts': {kDefaultAccountId: newDefaultAccount('PEN').toJson()},
      'categories': {for (final c in defaultCategories()) c.id: c.toJson()},
      'merchants': {},
      'movements': {},
      'subscriptions': {},
      'settings': {...settings},
    };

WalletDocs _with(String box, String id, Map<String, Object?> json, [WalletDocs? base]) {
  final out = {for (final e in (base ?? _fresh()).entries) e.key: {...e.value}};
  (out[box] ??= {})[id] = json;
  return out;
}

void main() {
  group('isEffectivelyEmpty', () {
    test('lo predeterminado y los ajustes cuentan como vacío', () {
      expect(isEffectivelyEmpty(_fresh()), isTrue);
      expect(
        isEffectivelyEmpty(_fresh(settings: {
          'wallet.settings': {'currency': 'USD', 'onboardingDone': true},
          'capture.sources': {'bcp': 'default'},
        })),
        isTrue,
      );
      expect(isEffectivelyEmpty({}), isTrue, reason: 'un teléfono recién instalado');
      expect(isEffectivelyEmpty(_with('merchants', 'cat.netflix', {'id': 'cat.netflix'})), isTrue);
    });

    test('un movimiento, una suscripción, un comercio propio o un saldo inicial no son vacío', () {
      expect(isEffectivelyEmpty(_with('movements', 'm1', {'id': 'm1'})), isFalse);
      expect(isEffectivelyEmpty(_with('subscriptions', 's1', {'id': 's1'})), isFalse);
      expect(isEffectivelyEmpty(_with('merchants', 'custom.1', {'id': 'custom.1'})), isFalse);
      expect(isEffectivelyEmpty(_with('accounts', 'bcp', {'id': 'bcp', 'initialMinor': 0})), isFalse);
      expect(
        isEffectivelyEmpty(_with('accounts', kDefaultAccountId, {...newDefaultAccount('PEN').toJson(), 'initialMinor': 500})),
        isFalse,
      );
      expect(isEffectivelyEmpty(_with('categories', 'mia', {'id': 'mia'})), isFalse);
    });
  });

  group('decideMigration', () {
    final full = _with('movements', 'm1', {'id': 'm1', 'amount': 1});
    final other = _with('movements', 'm2', {'id': 'm2', 'amount': 2});

    final table = <(String, WalletDocs, WalletDocs, String?, MigrationCase)>[
      ('local vacío, nube con datos', _fresh(), full, 'u1', MigrationCase.download),
      ('local sin dueño y vacío', _fresh(), full, null, MigrationCase.download),
      ('nube vacía, local con datos', full, {}, 'u1', MigrationCase.upload),
      ('nube vacía, local de vista previa', full, {}, 'preview', MigrationCase.upload),
      ('ambos vacíos: se sube lo predeterminado, no se borra', _fresh(), {}, 'u1', MigrationCase.upload),
      ('ambos con datos distintos', full, other, 'u1', MigrationCase.ask),
      ('local sin dueño con datos distintos', full, other, null, MigrationCase.ask),
      ('lo local ya está entero en la nube', full, _with('movements', 'm2', {'id': 'm2'}, full), 'u1', MigrationCase.download),
      ('lo local de otra cuenta', full, other, 'u0', MigrationCase.foreign),
      ('lo local de otra cuenta aunque la nube esté vacía', full, {}, 'u0', MigrationCase.foreign),
    ];
    for (final (name, local, cloud, owner, expected) in table) {
      test(name, () {
        expect(decideMigration(local: local, cloud: cloud, uid: 'u1', localOwner: owner), expected);
      });
    }

    test('el mismo id con otro contenido es un dato distinto', () {
      final cloud = _with('movements', 'm1', {'id': 'm1', 'amount': 9});
      expect(decideMigration(local: full, cloud: cloud, uid: 'u1', localOwner: 'u1'), MigrationCase.ask);
    });

    test('los campos del dispositivo de wallet.settings no cuentan como diferencia', () {
      final local = _with('settings', 'wallet.settings', {'currency': 'PEN', 'ownerUid': 'u1', 'faceIdEnabled': true}, full);
      final cloud = _with('settings', 'wallet.settings', {'currency': 'PEN'}, full);
      expect(decideMigration(local: local, cloud: cloud, uid: 'u1', localOwner: 'u1'), MigrationCase.download);
    });
  });

  group('mergeForUpload', () {
    test('solo sube los ids que no están en la nube; si están en ambos, gana la nube', () {
      final local = _with('movements', 'm1', {'id': 'm1', 'amount': 1});
      local['movements']!['m2'] = {'id': 'm2', 'amount': 2};
      local['accounts']![kDefaultAccountId] = {...newDefaultAccount('PEN').toJson(), 'initialMinor': 700};
      final cloud = <String, Map<String, Map<String, Object?>>>{
        'movements': {
          'm1': {'id': 'm1', 'amount': 100},
        },
        'accounts': {kDefaultAccountId: newDefaultAccount('PEN').toJson()},
        'categories': {for (final c in defaultCategories()) c.id: c.toJson()},
      };
      final up = mergeForUpload(local: local, cloud: cloud);
      expect(up['movements'], {
        'm2': {'id': 'm2', 'amount': 2},
      });
      expect(up['accounts'] ?? {}, isEmpty, reason: '"Mi cuenta" se une sin duplicarse');
      expect(up['categories'] ?? {}, isEmpty, reason: 'las predeterminadas no se duplican');
    });

    test('ajustes: gana la nube, se unen los conjuntos y el inicio es el más antiguo', () {
      final local = _fresh(settings: {
        'wallet.settings': {
          'currency': 'USD',
          'carryOver': false,
          'onboardingDone': true,
          'walletStartedAt': '2026-01-15T00:00:00.000',
          'deletedChargeIds': ['c1', 'c2'],
          'dismissedSplitMatchIds': ['d1'],
          'splitAccountIds': {'e1': 'bcp', 'e2': 'local'},
          'faceIdEnabled': true,
          'ownerUid': 'u1',
        },
        'capture.sources': {'bcp': 'bcp', 'yape': 'local'},
        'notifications.globalRule': {'daysBefore': 3},
      });
      final cloud = _fresh(settings: {
        'wallet.settings': {
          'currency': 'PEN',
          'carryOver': true,
          'onboardingDone': true,
          'walletStartedAt': '2026-03-01T00:00:00.000',
          'deletedChargeIds': ['c2', 'c3'],
          'dismissedSplitMatchIds': [],
          'splitAccountIds': {'e2': 'nube'},
        },
        'capture.sources': {'yape': 'nube'},
        'notifications.globalRule': {'daysBefore': 1},
      });
      final up = mergeForUpload(local: local, cloud: cloud)['settings']!;
      final w = up['wallet.settings']!;
      expect(w['currency'], 'PEN');
      expect(w['carryOver'], isTrue);
      expect(w['walletStartedAt'], '2026-01-15T00:00:00.000');
      expect(w['deletedChargeIds'], ['c1', 'c2', 'c3']);
      expect(w['dismissedSplitMatchIds'], ['d1']);
      expect(w['splitAccountIds'], {'e1': 'bcp', 'e2': 'nube'});
      expect(w.containsKey('faceIdEnabled'), isFalse, reason: 'lo del dispositivo no sube');
      expect(w.containsKey('ownerUid'), isFalse);
      expect(up['capture.sources'], {'bcp': 'bcp', 'yape': 'nube'});
      expect(up.containsKey('notifications.globalRule'), isFalse, reason: 'gana la nube: no hay nada que subir');
    });

    test('el inicio de la nube gana si es más antiguo; uno nulo no cuenta', () {
      WalletDocs s(String? started) => _fresh(settings: {
            'wallet.settings': {'currency': 'PEN', 'walletStartedAt': started},
          });
      expect(
        mergeForUpload(local: s('2026-05-01T00:00:00.000'), cloud: s('2026-02-01T00:00:00.000'))['settings']?['wallet.settings'],
        isNull,
        reason: 'nada cambia en la nube',
      );
      expect(
        mergeForUpload(local: s('2026-05-01T00:00:00.000'), cloud: s(null))['settings']!['wallet.settings']!['walletStartedAt'],
        '2026-05-01T00:00:00.000',
      );
      expect(mergeForUpload(local: s(null), cloud: s('2026-02-01T00:00:00.000'))['settings']?['wallet.settings'], isNull);
    });

    test('ajustes que la nube no tiene se suben tal cual (sin lo del dispositivo)', () {
      final local = _fresh(settings: {
        'wallet.settings': {'currency': 'USD', 'ownerUid': 'u1'},
        'notifications.globalRule': {'daysBefore': 2},
        'account.preview': {'signedIn': true},
      });
      final up = mergeForUpload(local: local, cloud: {})['settings']!;
      expect(up['wallet.settings'], {'currency': 'USD'});
      expect(up['notifications.globalRule'], {'daysBefore': 2});
      expect(up.containsKey('account.preview'), isFalse, reason: 'solo lo sincronizado');
    });
  });
}
