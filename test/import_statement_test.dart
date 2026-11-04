import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:outflow/core/di/core_providers.dart';
import 'package:outflow/core/domain/money.dart';
import 'package:outflow/core/utils/formatters.dart';
import 'package:outflow/features/account/domain/account.dart';
import 'package:outflow/features/account/presentation/session_controller.dart';
import 'package:outflow/features/statements/data/pdf_text_reader.dart';
import 'package:outflow/features/statements/data/statement_ai_reader.dart';
import 'package:outflow/features/statements/data/statement_file_reader.dart';
import 'package:outflow/features/statements/domain/import_statement.dart';
import 'package:outflow/features/statements/domain/statement.dart';
import 'package:outflow/features/statements/presentation/import_statement_screen.dart';
import 'package:outflow/features/subscriptions/domain/entities/subscription.dart';
import 'package:outflow/features/wallet/domain/account_balances.dart';
import 'package:outflow/features/wallet/domain/category.dart';
import 'package:outflow/features/wallet/domain/default_categories.dart';
import 'package:outflow/features/wallet/domain/month_summary.dart';
import 'package:outflow/features/wallet/domain/movement.dart';
import 'package:outflow/features/wallet/domain/wallet_account.dart';
import 'package:outflow/features/wallet/domain/wallet_settings.dart';
import 'package:outflow/features/wallet/presentation/wallet_providers.dart';

import 'support/fakes.dart';
import 'support/xlsx_fixture.dart';

const _holder = 'Lucía Prueba Ejemplo';
final _now = DateTime(2026, 11, 3, 12);

WalletAccount _acc(
  String id,
  String name, {
  bool isDefault = false,
  String currency = 'PEN',
  int initial = 100000,
  DateTime? since,
  String? digits,
}) =>
    WalletAccount(
      id: id,
      name: name,
      type: AccountType.bank,
      currency: currency,
      initialMinor: initial,
      initialDate: since ?? kAccountBeginning,
      isDefault: isDefault,
      lastDigits: digits,
    );

final _scotia = _acc('scotia', 'Scotiabank', isDefault: true);
final _dale = _acc('dale', 'Dale');

StatementRow _row(int day, int minor, {bool credit = false, String text = 'Transf. plin', int month = 10, String? op}) =>
    StatementRow(date: DateTime(2026, month, day), description: text, amountMinor: minor, isCredit: credit, operationId: op);

Movement _m(
  String id,
  int minor, {
  MovementKind kind = MovementKind.expense,
  String? account = 'scotia',
  String? to,
  bool incoming = false,
  int day = 3,
  MovementOrigin origin = MovementOrigin.capture,
  bool review = false,
  String title = 'Tambo',
  String? ref,
  int month = 10,
}) =>
    Movement(
      id: id,
      kind: kind,
      amount: Money(minor, 'PEN'),
      categoryId: kind == MovementKind.expense
          ? 'food'
          : kind == MovementKind.income
              ? kOtherIncomeCategoryId
              : kNoCategoryId,
      date: DateTime(2026, month, day, 9),
      createdAt: DateTime(2026, month, day, 9),
      title: title,
      origin: origin,
      accountId: account,
      toAccountId: to,
      transferIncoming: incoming,
      needsReview: review,
      externalRef: ref,
    );

List<RowStatus> _statuses(List<(StatementRow, RowStatus)> r) => [for (final x in r) x.$2];

/// Selector de archivos que entrega lo que se le indique.
class _Picker implements StatementFilePicker {
  _Picker(this.files);
  final List<PickedStatement?> files;
  @override
  Future<PickedStatement?> pick() async => files.removeAt(0);
}

class _Picked implements PickedStatement {
  _Picked(this.name, this.bytes);
  _Picked.csv(String content) : name = 'movimientos.csv', bytes = Uint8List.fromList(utf8.encode(content));
  @override
  final String name;
  final Uint8List bytes;
  int discards = 0;
  @override
  String? get path => 'C:/tmp/$name';
  @override
  Future<Uint8List> readBytes() async => bytes;
  @override
  Future<void> discard() async => discards++;
}

/// Lector de PDF con contraseña: registra lo que se intentó.
class _Pdf implements PdfTextReader {
  _Pdf(this.text, {this.password});
  final String text;
  final String? password;
  final tried = <String?>[];
  @override
  Future<String> read(String path, {String? password}) async {
    tried.add(password);
    if (this.password != null) {
      if (password == null) throw const PdfPasswordRequired();
      if (password != this.password) throw const PdfWrongPassword();
    }
    return text;
  }
}

const _csvHeader = 'Titular:,$_holder,\nCuenta:,Cuenta Digital SBP Soles **** 1234,\nFecha,Descripción,Importe S/\n';

void main() {
  group('classifyDescription', () {
    final accounts = [_scotia, _dale];
    RowKind kind(String d, bool credit, {String? holder = _holder, String? google}) =>
        classifyDescription(d, credit, holder: holder, accountHolder: google, accounts: accounts);

    test('cuentas propias con ambos signos', () {
      expect(kind('Transf.inmed.cce ctas.propias', false), RowKind.transfer);
      expect(kind('TRANSF.INMED.CCE CTAS.PROPIAS', true), RowKind.transfer);
    });

    test('Dale con el titular truncado es transferencia, en ambos sentidos', () {
      expect(kind('Dale-Lucia Prueba Ejem', false), RowKind.transfer);
      expect(kind('DALE-LUCÍA  PRUEBA EJEMPLO', true), RowKind.transfer);
      expect(ownAccountIn('Dale-Lucia Prueba Ejem', holder: _holder, accounts: accounts)?.id, 'dale');
    });

    test('el titular también puede venir de la cuenta de Google', () {
      expect(kind('Dale-Lucia Prueba', false, holder: null, google: _holder), RowKind.transfer);
      expect(kind('Dale-Lucia Prueba', false, holder: 'Otro Nombre', google: _holder), RowKind.transfer);
    });

    test('Dale con otro nombre, o sin titular conocido, no es una cuenta propia', () {
      expect(kind('Dale-Mario Otra Persona', false), RowKind.expense);
      expect(kind('Dale-Lucia Prueba', false, holder: null), RowKind.expense);
    });

    test('Yape o Plin de otra persona va por el signo', () {
      expect(kind('Yape-Mario Otra Persona', true), RowKind.income);
      expect(kind('Plin-Mario Otra Persona', true), RowKind.income);
      expect(kind('Yape-Mario Otra Persona', false), RowKind.expense);
    });

    test('impuesto e ITF son comisión', () {
      expect(kind('Impuesto a los creditos', false), RowKind.fee);
      expect(kind('IMPUESTO A LOS CRÉDITOS', false), RowKind.fee);
      expect(kind('ITF', false), RowKind.fee);
      expect(kind('Comprita de pitfall', false), RowKind.expense);
    });

    test('lo desconocido va por el signo', () {
      expect(kind('Punto marisko', false), RowKind.expense);
      expect(kind('Trf.cce pago proveedores', true), RowKind.income);
      expect(kind('Transf. plin', false), RowKind.expense);
      expect(kind('Debito - compras', false), RowKind.expense);
    });
  });

  group('classifyRows', () {
    test('seis filas iguales con dos registradas: dos ya están y cuatro son nuevas', () {
      final rows = List.generate(6, (_) => _row(3, 50000));
      final movements = [_m('a', 50000), _m('b', 50000)];
      expect(
        _statuses(classifyRows(rows, _scotia, movements)),
        [RowStatus.alreadyThere, RowStatus.alreadyThere, RowStatus.fresh, RowStatus.fresh, RowStatus.fresh, RowStatus.fresh],
      );
    });

    test('importar dos veces el mismo archivo no crea nada nuevo', () {
      final rows = [...List.generate(6, (_) => _row(3, 50000)), _row(4, 100, credit: true)];
      final preview = buildPreview(rows: rows, account: _scotia, accounts: [_scotia, _dale], movements: const [], now: _now);
      final created = buildImport(
        preview: preview,
        selected: {for (var i = 0; i < rows.length; i++) i},
        account: _scotia,
        accounts: [_scotia, _dale],
        categories: defaultCategories(),
        history: const [],
        now: _now,
      );
      expect(created, hasLength(7));
      expect(_statuses(classifyRows(rows, _scotia, created)).toSet(), {RowStatus.alreadyThere});
    });

    test('un movimiento sin cuenta es de la cuenta por defecto', () {
      final legacy = _m('a', 500, account: null);
      expect(_statuses(classifyRows([_row(3, 500)], _scotia, [legacy])), [RowStatus.alreadyThere]);
      expect(_statuses(classifyRows([_row(3, 500)], _dale, [legacy], defaultAccountId: 'scotia')), [RowStatus.fresh]);
    });

    test('otra cuenta, otro importe, otro sentido u otra fecha no coinciden', () {
      final row = _row(3, 500);
      expect(_statuses(classifyRows([row], _scotia, [_m('a', 500, account: 'dale')])), [RowStatus.fresh]);
      expect(_statuses(classifyRows([row], _scotia, [_m('a', 501)])), [RowStatus.fresh]);
      expect(_statuses(classifyRows([row], _scotia, [_m('a', 500, kind: MovementKind.income)])), [RowStatus.fresh]);
      expect(_statuses(classifyRows([row], _scotia, [_m('a', 500, day: 5)])), [RowStatus.fresh]);
    });

    test('un día de diferencia sí coincide, aunque la descripción sea otra', () {
      expect(_statuses(classifyRows([_row(3, 500, text: 'Debito - compras')], _scotia, [_m('a', 500, day: 2, title: 'Tambo')])), [RowStatus.alreadyThere]);
      expect(_statuses(classifyRows([_row(3, 500)], _scotia, [_m('a', 500, day: 4)])), [RowStatus.alreadyThere]);
    });

    test('cada movimiento absorbe una fila, y la del mismo día tiene preferencia', () {
      final rows = [_row(2, 500), _row(3, 500)];
      expect(_statuses(classifyRows(rows, _scotia, [_m('a', 500, day: 3)])), [RowStatus.fresh, RowStatus.alreadyThere]);
    });

    test('Review Focus 2: una fila igual a un "por revisar" ya está y no se toca', () {
      final pending = _m('a', 500, review: true);
      final preview = buildPreview(rows: [_row(3, 500)], account: _scotia, accounts: [_scotia], movements: [pending], now: _now);
      expect(preview.single.status, RowStatus.alreadyThere);
      expect(preview.single.link, isNull);
      expect(
        buildImport(
          preview: preview,
          selected: const {},
          account: _scotia,
          accounts: [_scotia],
          categories: defaultCategories(),
          history: [pending],
          now: _now,
        ),
        isEmpty,
      );
    });

    test('la misma referencia ya está; dos referencias distintas son dos operaciones', () {
      expect(_statuses(classifyRows([_row(20, 500, op: 'X1')], _scotia, [_m('a', 700, ref: 'x1')])), [RowStatus.alreadyThere]);
      expect(_statuses(classifyRows([_row(3, 500, op: 'X1')], _scotia, [_m('a', 500, ref: 'X2')])), [RowStatus.fresh]);
    });

    test('los cobros de suscripción y los ajustes no absorben filas', () {
      final sub = _m('a', 500, origin: MovementOrigin.subscription);
      final adj = _m('b', 500, kind: MovementKind.adjustment);
      expect(_statuses(classifyRows([_row(3, 500)], _scotia, [sub, adj])), [RowStatus.fresh]);
    });

    test('la transferencia que entra por el otro lado cuenta como de esta cuenta', () {
      final transfer = _m('t', 400, kind: MovementKind.transfer, account: 'scotia', to: 'dale', origin: MovementOrigin.statement);
      expect(_statuses(classifyRows([_row(3, 400, credit: true, text: 'Scotiabank-Lucia')], _dale, [transfer])), [RowStatus.alreadyThere]);
    });
  });

  group('movimientos que crea la importación', () {
    final accounts = [_scotia, _dale];
    final categories = defaultCategories();

    List<Movement> importAll(List<StatementRow> rows, {List<Movement> existing = const [], Map<int, RowChoice> overrides = const {}}) {
      final preview = buildPreview(
        rows: rows,
        account: _scotia,
        accounts: accounts,
        movements: existing,
        holder: _holder,
        now: _now,
        overrides: overrides,
      );
      return buildImport(
        preview: preview,
        selected: {for (var i = 0; i < rows.length; i++) if (preview[i].status == RowStatus.fresh) i},
        account: _scotia,
        accounts: accounts,
        categories: categories,
        history: existing,
        now: _now,
      );
    }

    test('gasto, ingreso y comisión: origen statement, sin revisar y con categoría', () {
      final made = importAll([
        _row(3, 1500, text: 'Uber trip'),
        _row(4, 9000, credit: true, text: 'Yape-Mario Otra Persona'),
        _row(4, 900, credit: true, text: 'Abono varios'),
        _row(5, 20, text: 'Impuesto a los creditos'),
        _row(6, 700, text: 'Punto marisko'),
      ]);
      expect(made.map((m) => m.origin).toSet(), {MovementOrigin.statement});
      expect(made.map((m) => m.needsReview).toSet(), {false});
      expect(made.map((m) => m.accountId).toSet(), {'scotia'});
      expect(made.map((m) => m.kind), [MovementKind.expense, MovementKind.income, MovementKind.income, MovementKind.expense, MovementKind.expense]);
      expect(made.map((m) => m.categoryId), ['transport', 'transfer_in', kOtherIncomeCategoryId, 'expense_other', 'expense_other']);
      expect(made[0].title, 'Uber trip');
      expect(made[0].date, DateTime(2026, 10, 3));
      expect(made[0].createdAt, _now);
      expect(made[0].amount, const Money(1500, 'PEN'));
    });

    test('la comisión usa una categoría de comisiones si existe', () {
      const fees = Category(id: 'bank_fees', name: 'Comisiones', kind: MovementKind.expense, icon: 'ellipsis', color: 0xFF8E8E93);
      final preview = buildPreview(rows: [_row(5, 20, text: 'ITF')], account: _scotia, accounts: accounts, movements: const [], now: _now);
      final made = buildImport(
        preview: preview,
        selected: {0},
        account: _scotia,
        accounts: accounts,
        categories: [...categories, fees],
        history: const [],
        now: _now,
      );
      expect(made.single.categoryId, fees.id);
    });

    test('transferencia con destino conocido, en cada sentido, y saldos', () {
      final out = importAll([_row(3, 400, text: 'Dale-Lucia Prueba Ejem')]).single;
      expect((out.kind, out.accountId, out.toAccountId), (MovementKind.transfer, 'scotia', 'dale'));
      expect(out.categoryId, kNoCategoryId);
      expect(out.origin, MovementOrigin.statement);
      final balances = computeBalances(accounts, [out]);
      expect(balances['scotia'], 100000 - 400);
      expect(balances['dale'], 100000 + 400);

      final back = importAll([_row(3, 400, credit: true, text: 'Dale-Lucia Prueba Ejem')]).single;
      expect((back.accountId, back.toAccountId), ('dale', 'scotia'));
    });

    test('transferencia sin destino conocido: sin toAccountId y sentido por el signo', () {
      final out = importAll([_row(3, 400, text: 'Transf.inmed.cce ctas.propias')]).single;
      expect((out.kind, out.accountId, out.toAccountId, out.transferIncoming), (MovementKind.transfer, 'scotia', null, false));
      final inbound = importAll([_row(3, 400, credit: true, text: 'Transf.inmed.cce ctas.propias')]).single;
      expect((inbound.toAccountId, inbound.transferIncoming), (null, true));
      expect(computeBalances(accounts, [inbound])['scotia'], 100400);
    });

    test('si la otra cuenta ya tiene el lado opuesto sin destino, se enlaza y no se duplica', () {
      final other = _m('o', 400, kind: MovementKind.transfer, account: 'dale', incoming: true, origin: MovementOrigin.statement);
      final rows = [_row(3, 400, text: 'Dale-Lucia Prueba Ejem')];
      final preview = buildPreview(rows: rows, account: _scotia, accounts: accounts, movements: [other], holder: _holder, now: _now);
      expect(preview.single.status, RowStatus.alreadyThere);
      expect(preview.single.link?.id, 'o');
      expect(_statuses(classifyRows(rows, _scotia, [other], accounts: accounts, holder: _holder)), [RowStatus.alreadyThere]);

      final made = importAll(rows, existing: [other]);
      expect(made.single.id, 'o');
      expect((made.single.accountId, made.single.toAccountId), ('scotia', 'dale'));
      final balances = computeBalances(accounts, made);
      expect(balances['scotia'], 100000 - 400);
      expect(balances['dale'], 100000 + 400, reason: 'el otro lado sigue sumando una sola vez');
    });

    test('un ingreso capturado en la otra cuenta se convierte en la transferencia, sin confirmarlo', () {
      final other = _m('o', 400, kind: MovementKind.income, account: 'dale', review: true);
      final made = importAll([_row(3, 400, text: 'Dale-Lucia Prueba Ejem')], existing: [other]);
      expect(made.single.id, 'o');
      expect(made.single.kind, MovementKind.transfer);
      expect((made.single.accountId, made.single.toAccountId), ('scotia', 'dale'));
      expect(made.single.categoryId, kNoCategoryId);
      expect(made.single.needsReview, isTrue);
    });

    test('Formatos reales: recarga en Scotiabank y gasto de Lemon desde Dale no se enlazan', () {
      final lemon = _m('l', 400, account: 'dale', title: 'Otra Persona');
      final made = importAll([_row(3, 400, text: 'Dale-Lucia Prueba Ejem')], existing: [lemon]);
      expect(made.single.id, isNot('l'));
      expect((made.single.accountId, made.single.toAccountId), ('scotia', 'dale'));
    });

    test('la otra cuenta en otra moneda deja el destino sin registrar', () {
      final usd = _acc('usd', 'Dale', currency: 'USD');
      final preview = buildPreview(rows: [_row(3, 400, text: 'Dale-Lucia Prueba')], account: _scotia, accounts: [_scotia, usd], movements: const [], holder: _holder, now: _now);
      expect(preview.single.kind, RowKind.transfer);
      expect(preview.single.other, isNull);
    });

    test('el tipo de una fila se puede cambiar', () {
      final rows = [_row(3, 400, text: 'Transf. plin')];
      final toDale = importAll(rows, overrides: {0: const RowChoice(RowKind.transfer, otherAccountId: 'dale')}).single;
      expect((toDale.kind, toDale.toAccountId), (MovementKind.transfer, 'dale'));
      final unknown = importAll(rows, overrides: {0: const RowChoice(RowKind.transfer)}).single;
      expect((unknown.kind, unknown.toAccountId), (MovementKind.transfer, null));
      final fee = importAll(rows, overrides: {0: const RowChoice(RowKind.fee)}).single;
      expect(fee.kind, MovementKind.expense);
    });
  });

  group('filas anteriores al saldo', () {
    final since = DateTime(2026, 11, 1);
    final account = _acc('scotia', 'Scotiabank', isDefault: true, since: since);

    test('anteriores a la fecha inicial: la vista previa lo avisa y no mueven el saldo', () {
      final rows = [_row(3, 500), _row(4, 900, credit: true), _row(2, 100, month: 11)];
      final preview = buildPreview(rows: rows, account: account, accounts: [account], movements: const [], now: _now);
      expect(preview.map((r) => r.movesBalance), [false, false, true]);

      final made = buildImport(
        preview: preview,
        selected: {0, 1},
        account: account,
        accounts: [account],
        categories: defaultCategories(),
        history: const [],
        now: _now,
      );
      expect(computeBalances([account], made)['scotia'], 100000);
      // En el historial y el Resumen sí aparecen.
      expect(made, hasLength(2));
      final summary = MonthSummary.compute(
        movements: made,
        subscriptions: const <Subscription>[],
        settings: WalletSettings(walletStartedAt: DateTime(2026, 1, 1), currency: 'PEN'),
        month: DateTime(2026, 10),
        now: _now,
      );
      expect(summary.expense.minor, 500);
      expect(summary.income.minor, 900);
    });

    test('anteriores a un ajuste y apuntadas después: tampoco mueven el saldo', () {
      final open = _acc('scotia', 'Scotiabank', isDefault: true);
      final adjustment = makeAdjustment(account: open, currentMinor: 100000, realMinor: 120000, now: DateTime(2026, 10, 20))!;
      final preview = buildPreview(rows: [_row(3, 500), _row(25, 500)], account: open, accounts: [open], movements: [adjustment], now: _now);
      expect(preview.map((r) => r.movesBalance), [false, true]);
      final made = buildImport(
        preview: preview,
        selected: {0},
        account: open,
        accounts: [open],
        categories: defaultCategories(),
        history: [adjustment],
        now: _now,
      );
      expect(computeBalances([open], [adjustment, ...made])['scotia'], 120000);
    });
  });

  group('pantalla', () {
    late MemoryMovements movements;
    late MemoryAccounts accounts;

    Future<void> pump(
      WidgetTester tester, {
      required List<PickedStatement?> files,
      List<WalletAccount>? accountList,
      List<Movement> existing = const [],
      PdfTextReader? pdf,
      StatementAiReader? ai,
      Size size = const Size(1080, 2400),
      double textScale = 1,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      movements = MemoryMovements(existing);
      accounts = MemoryAccounts(accountList ?? [_scotia, _dale], movements);
      final settings = MemorySettings(WalletSettings(walletStartedAt: DateTime(2026, 1, 1), currency: 'PEN'));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          movementRepositoryProvider.overrideWithValue(movements),
          accountRepositoryProvider.overrideWithValue(accounts),
          walletSettingsRepositoryProvider.overrideWithValue(settings),
          nowProvider.overrideWithValue(_now),
          categoriesProvider.overrideWith((ref) => Stream.value(defaultCategories())),
          currentAccountProvider.overrideWithValue(const Account(uid: 'u', email: 'l@example.com', displayName: _holder)),
          statementFilePickerProvider.overrideWithValue(_Picker([...files])),
          pdfTextReaderProvider.overrideWithValue(pdf ?? _Pdf('')),
          statementAiReaderProvider.overrideWithValue(ai),
        ],
        child: MediaQuery(
          data: MediaQueryData(size: size / 3, textScaler: TextScaler.linear(textScale)),
          child: const MaterialApp(home: ImportStatementScreen()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> chooseFile(WidgetTester tester) async {
      await tester.tap(find.text('Elegir archivo'));
      await tester.pumpAndSettle();
    }

    testWidgets('vista previa con Nueva y Ya registrada: importar crea solo las marcadas', (tester) async {
      final file = _Picked.csv(
        '${_csvHeader}3/10/2026,Transf. plin,-500.00\n'
        '3/10/2026,Transf. plin,-500.00\n'
        '4/10/2026,Punto marisko,-12.50\n'
        '5/10/2026,Yape-Mario Otra Persona,20.00\n',
      );
      await pump(tester, files: [file], existing: [_m('a', 50000)]);
      await chooseFile(tester);

      expect(find.text('Nueva'), findsNWidgets(3));
      expect(find.text('Ya registrada'), findsOneWidget);
      expect(find.text('Importar 3 movimientos'), findsOneWidget);
      expect(file.discards, 1, reason: 'el archivo no se guarda');

      // Desmarca "Punto marisko".
      await tester.tap(find.byKey(const ValueKey('row_2')));
      await tester.pump();
      expect(find.text('Importar 2 movimientos'), findsOneWidget);

      await tester.tap(find.text('Importar 2 movimientos'));
      await tester.pumpAndSettle();

      final created = movements.saved.where((m) => m.origin == MovementOrigin.statement).toList();
      expect(created, hasLength(2));
      expect(created.map((m) => m.title).toSet(), {'Transf. plin', 'Yape-Mario Otra Persona'});
      expect(created.map((m) => m.needsReview).toSet(), {false});
      expect(find.textContaining('Se importaron 2 movimientos'), findsOneWidget);
    });

    testWidgets('los dígitos del archivo eligen la cuenta', (tester) async {
      final digits = _acc('other', 'Otra', digits: '1234');
      await pump(
        tester,
        files: [_Picked.csv('${_csvHeader}3/10/2026,Compra,-500.00\n')],
        accountList: [_scotia, digits],
      );
      await chooseFile(tester);
      await tester.tap(find.text('Importar 1 movimiento'));
      await tester.pumpAndSettle();
      expect(movements.saved.single.accountId, 'other');
    });

    testWidgets('xlsx de punta a punta: fila vacía al final, Dale como Transferencia', (tester) async {
      final bytes = buildXlsx([
        [const XCell.text('Titular:'), const XCell.text(_holder)],
        [const XCell.text('Fecha'), const XCell.text('Descripción'), const XCell.text('Importe S/')],
        [const XCell.text('3/10/2026'), const XCell.text('Dale-Lucia Prueba Ejem'), const XCell.number('-4')],
      ], sparseRows: 50);
      await pump(tester, files: [_Picked('movimientos.xlsx', bytes)]);
      await chooseFile(tester);
      expect(find.text('Transferencia'), findsOneWidget);
      await tester.tap(find.text('Importar 1 movimiento'));
      await tester.pumpAndSettle();
      expect(movements.saved.single.toAccountId, 'dale');
    });

    testWidgets('se puede cambiar el tipo de una fila', (tester) async {
      await pump(tester, files: [_Picked.csv('${_csvHeader}3/10/2026,Transf. plin,-500.00\n')]);
      await chooseFile(tester);
      expect(find.text('Gasto'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('kind_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transferencia a Dale'));
      await tester.pumpAndSettle();
      expect(find.text('Transferencia'), findsOneWidget);
      await tester.tap(find.text('Importar 1 movimiento'));
      await tester.pumpAndSettle();
      expect(movements.saved.single.toAccountId, 'dale');
    });

    testWidgets('avisa de las filas anteriores al saldo y no lo mueve', (tester) async {
      final account = _acc('scotia', 'Scotiabank', isDefault: true, since: DateTime(2026, 11, 1));
      await pump(tester, files: [_Picked.csv('${_csvHeader}3/10/2026,Compra,-500.00\n')], accountList: [account]);
      await chooseFile(tester);
      expect(
        find.text('Estas filas son anteriores a tu saldo inicial: se registran en tu historial pero no cambian el saldo.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Importar 1 movimiento'));
      await tester.pumpAndSettle();
      expect(movements.saved, hasLength(1));
      expect(computeBalances([account], movements.saved)['scotia'], 100000);
    });

    testWidgets('sin saldo final no se ofrece ajuste', (tester) async {
      await pump(tester, files: [_Picked.csv('${_csvHeader}3/10/2026,Compra,-500.00\n')]);
      await chooseFile(tester);
      await tester.tap(find.text('Importar 1 movimiento'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ajustar a'), findsNothing);
    });

    testWidgets('con saldo final distinto ofrece el ajuste, y al ajustar coincide', (tester) async {
      const csv = 'Fecha,Concepto,Importe,Saldo\n3/10/2026,Compra,-5.00,250.00\n';
      await pump(tester, files: [_Picked.csv(csv)]);
      await chooseFile(tester);
      await tester.tap(find.text('Importar 1 movimiento'));
      await tester.pumpAndSettle();
      final label = 'Ajustar a ${Fmt.money(const Money(25000, 'PEN'))}';
      expect(find.text(label), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(computeBalances([_scotia, _dale], movements.saved)['scotia'], 25000);
      expect(movements.saved.where((m) => m.kind == MovementKind.adjustment), hasLength(1));
      expect(find.text(label), findsNothing);
    });

    testWidgets('con saldo final igual no ofrece ajuste', (tester) async {
      const csv = 'Fecha,Concepto,Importe,Saldo\n3/10/2026,Compra,-5.00,995.00\n';
      await pump(tester, files: [_Picked.csv(csv)]);
      await chooseFile(tester);
      await tester.tap(find.text('Importar 1 movimiento'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ajustar a'), findsNothing);
    });

    group('PDF', () {
      const text = 'Cuenta Soles\n03/10/2026 Compra -5.00\n';

      // El cursor de un campo con foco parpadea siempre: pumpAndSettle no terminaría.
      Future<void> settle(WidgetTester tester) async {
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      testWidgets('con contraseña la pide, repite si es incorrecta y luego lee', (tester) async {
        final pdf = _Pdf(text, password: 'secreto');
        final file = _Picked('estado.pdf', Uint8List(0));
        await pump(tester, files: [file], pdf: pdf);
        await tester.tap(find.text('Elegir archivo'));
        await settle(tester);

        expect(find.text('Este PDF tiene contraseña'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'mala');
        await tester.tap(find.text('Abrir'));
        await settle(tester);

        expect(find.text('Esa contraseña no es correcta.'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'secreto');
        await tester.tap(find.text('Abrir'));
        await settle(tester);

        expect(pdf.tried, [null, 'mala', 'secreto']);
        expect(find.text('Importar 1 movimiento'), findsOneWidget);
        expect(file.discards, 1);
      });

      testWidgets('cancelar la contraseña vuelve al inicio y borra la copia', (tester) async {
        final file = _Picked('estado.pdf', Uint8List(0));
        await pump(tester, files: [file], pdf: _Pdf(text, password: 'x'));
        await tester.tap(find.text('Elegir archivo'));
        await settle(tester);
        await tester.tap(find.text('Cancelar'));
        await settle(tester);
        expect(find.text('Elegir archivo'), findsOneWidget);
        expect(file.discards, 1);
      });

      testWidgets('un PDF de solo imagen lo explica y sugiere Excel', (tester) async {
        await pump(tester, files: [_Picked('estado.pdf', Uint8List(0))], pdf: _Pdf('  \n '));
        await chooseFile(tester);
        expect(find.textContaining('solo imágenes'), findsOneWidget);
        expect(find.textContaining('Excel'), findsWidgets);
      });
    });

    testWidgets('.xls antiguo muestra el mensaje', (tester) async {
      await pump(tester, files: [_Picked('m.xls', Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0]))]);
      await chooseFile(tester);
      expect(find.text('Guárdalo como .xlsx o CSV'), findsOneWidget);
    });

    testWidgets('formato desconocido: se eligen las columnas', (tester) async {
      await pump(tester, files: [_Picked.csv('a,b,c\n3/10/2026,Compra,-5.00\n')]);
      await chooseFile(tester);
      expect(find.text('Elige las columnas'), findsOneWidget);

      Future<void> choose(String field, String item) async {
        await tester.tap(find.byKey(ValueKey('column_$field')));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining(item).last);
        await tester.pumpAndSettle();
      }

      await choose('date', '3/10/2026');
      await choose('description', 'Compra');
      await choose('amount', '-5.00');
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(find.text('Importar 1 movimiento'), findsOneWidget);
    });

    group('IA', () {
      GeminiStatementReader reader(List<http.Request> sent) => GeminiStatementReader(
            MockClient((req) async {
              sent.add(req);
              return http.Response.bytes(
                utf8.encode(jsonEncode({
                  'candidates': [
                    {
                      'content': {
                        'parts': [
                          {
                            'text': jsonEncode({
                              'rows': [
                                {'date': '2026-10-03', 'description': 'Compra IA', 'amount': -5},
                              ],
                            }),
                          },
                        ],
                      },
                    },
                  ],
                })),
                200,
              );
            }),
            apiKey: 'k',
            model: 'm',
          );

      const unreadable = 'Cuenta 19112345678901\nCompra de algo por cinco soles\n';

      testWidgets('sin el interruptor no se llama a Gemini; con él, solo el texto enmascarado', (tester) async {
        final sent = <http.Request>[];
        await pump(tester, files: [_Picked('estado.pdf', Uint8List(0))], pdf: _Pdf(unreadable), ai: reader(sent));
        await chooseFile(tester);

        expect(find.text('Usar IA para leer este archivo'), findsOneWidget);
        final toggle = tester.widget<Switch>(find.descendant(of: find.byKey(const ValueKey('useAi')), matching: find.byType(Switch)));
        expect(toggle.value, isFalse);
        expect(sent, isEmpty);

        await tester.tap(find.byKey(const ValueKey('useAi')));
        await tester.pumpAndSettle();

        expect(sent, hasLength(1));
        expect(sent.single.body, isNot(contains('19112345678901')));
        expect(find.text('Compra IA'), findsOneWidget);
      });

      testWidgets('sin clave no aparece', (tester) async {
        await pump(tester, files: [_Picked('estado.pdf', Uint8List(0))], pdf: _Pdf(unreadable));
        await chooseFile(tester);
        expect(find.text('Usar IA para leer este archivo'), findsNothing);
      });

      testWidgets('con filas leídas solo aparece si se pide', (tester) async {
        final sent = <http.Request>[];
        await pump(tester, files: [_Picked.csv('${_csvHeader}3/10/2026,Compra,-500.00\n')], ai: reader(sent));
        await chooseFile(tester);
        expect(find.text('Usar IA para leer este archivo'), findsNothing);
        await tester.tap(find.text('¿Faltan filas? Leer con IA'));
        await tester.pumpAndSettle();
        expect(find.text('Usar IA para leer este archivo'), findsOneWidget);
        expect(sent, isEmpty);
      });
    });

    testWidgets('sin desbordes a 360 px y con letra grande', (tester) async {
      final long = 'Transferencia con una descripción larguísima que no cabe en una línea ${'x' * 40}';
      await pump(
        tester,
        files: [
          _Picked.csv('${_csvHeader}3/10/2026,$long,-1250000.50\n3/10/2026,Dale-Lucia Prueba Ejem,1250000.50\n3/10/2026,ITF,-0.50\n'),
        ],
        existing: [_m('a', 50, title: 'ITF')],
        textScale: 1.5,
      );
      expect(tester.takeException(), isNull);
      await chooseFile(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.textContaining('Importar ').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
