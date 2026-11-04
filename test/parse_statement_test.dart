import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/statements/data/statement_file_reader.dart';
import 'package:outflow/features/statements/data/xlsx_table_reader.dart';
import 'package:outflow/features/statements/domain/parse_statement.dart';

import 'support/xlsx_fixture.dart';

const _holder = 'Lucía Prueba Ejemplo';

/// Estado de cuenta inventado con la forma real de Scotiabank.
List<List<String>> _scotia() => [
      ['Movimientos de cuenta', '', ''],
      ['', '', ''],
      ['Titular:', _holder, ''],
      ['Cuenta:', 'Cuenta Digital SBP Soles **** 1234', ''],
      ['Desde:', '1/10/2026', ''],
      ['Hasta:', '31/10/2026', ''],
      ['', '', ''],
      ['Fecha', 'Descripción', 'Importe S/'],
      ['1/10/2026', 'Debito - compras', '-45.58'],
      ['2/10/2026', 'Trf.cce pago proveedores', '3000.00'],
      ['15/10/2026', 'Punto marisko', '-12.50'],
      ['', '', ''],
      ['', '', ''],
      ['Este documento es informativo y no constituye un estado de cuenta oficial.', '', ''],
      ['', '', ''],
    ];

void main() {
  group('tabla con el formato de Scotiabank', () {
    test('lee cabecera, fechas d/m/yyyy, importe con signo e ignora lo demás', () {
      final table = _scotia();
      final mapping = detectColumns(table)!;
      final parsed = parseStatementTable(table, mapping, fallbackCurrency: 'USD');

      expect(parsed.rows, hasLength(3));
      expect(parsed.rows[0].date, DateTime(2026, 10, 1));
      expect(parsed.rows[0].description, 'Debito - compras');
      expect(parsed.rows[0].amountMinor, 4558);
      expect(parsed.rows[0].isCredit, isFalse);
      expect(parsed.rows[1].amountMinor, 300000);
      expect(parsed.rows[1].isCredit, isTrue);
      expect(parsed.rows[2].date, DateTime(2026, 10, 15));
      expect(parsed.closingBalanceMinor, isNull);
      // "Importe S/" dice la moneda, aunque se pida otra por defecto.
      expect(parsed.currency, 'PEN');
    });

    test('la cabecera da titular, dígitos y periodo', () {
      final meta = readStatementMeta(_scotia());
      expect(meta.holder, _holder);
      expect(meta.accountDigits, '1234');
      expect(meta.from, DateTime(2026, 10, 1));
      expect(meta.to, DateTime(2026, 10, 31));
    });

    test('la cabecera también se lee con etiqueta y valor en la misma celda', () {
      final meta = readStatementMeta([
        ['Titular: $_holder'],
        ['Cuenta: Cuenta Digital SBP Soles **** 1234'],
        ['Desde: 1/10/2026'],
        ['Hasta: 31/10/2026'],
        ['Fecha', 'Descripción', 'Importe S/'],
      ]);
      expect(meta.holder, _holder);
      expect(meta.accountDigits, '1234');
      expect(meta.to, DateTime(2026, 10, 31));
    });

    test('seis filas iguales son seis filas', () {
      final table = [
        ['Fecha', 'Descripción', 'Importe S/'],
        for (var i = 0; i < 6; i++) ['3/10/2026', 'Transf. plin', '-500.00'],
      ];
      expect(parseStatementTable(table, detectColumns(table)!, fallbackCurrency: 'PEN').rows, hasLength(6));
    });

    test('totales, saldos e importes vacíos o en cero no son movimientos', () {
      final table = [
        ['Fecha', 'Descripción', 'Importe S/'],
        ['1/10/2026', 'Saldo anterior', '100.00'],
        ['1/10/2026', 'Compra', '-1.00'],
        ['1/10/2026', 'Sin importe', ''],
        ['1/10/2026', 'Cero', '0.00'],
        ['31/10/2026', 'Total', '-1.00'],
        ['Total', '', '-1.00'],
        ['Fecha', 'Descripción', 'Importe S/'],
        ['31/15/2026', 'Fecha imposible', '-1.00'],
      ];
      final rows = parseStatementTable(table, detectColumns(table)!, fallbackCurrency: 'PEN').rows;
      expect(rows.map((r) => r.description), ['Compra']);
    });

    test('acepta fecha dd/mm/yyyy, número de serie de Excel e importes en texto o número', () {
      final serial = excelSerial(DateTime(2026, 10, 9));
      final table = [
        ['Fecha', 'Descripción', 'Importe'],
        ['09/10/2026', 'Con ceros', 'S/ -1,250.50'],
        ['$serial', 'Serie', '-45.5'],
        ['$serial.0', 'Serie decimal', '1000'],
        ['10/10/2026 14:30', 'Con hora', '(20.00)'],
        ['10/10/2026', 'Signo detrás', '20.00-'],
        ['10/10/2026', 'Signo tipográfico', '−30.00'],
      ];
      final rows = parseStatementTable(table, detectColumns(table)!, fallbackCurrency: 'PEN').rows;
      expect(rows.map((r) => r.date).toSet(), {DateTime(2026, 10, 9), DateTime(2026, 10, 10)});
      expect(rows[0].amountMinor, 125050);
      expect(rows[0].isCredit, isFalse);
      expect(rows[1].date, DateTime(2026, 10, 9));
      expect(rows[1].amountMinor, 4550);
      expect(rows[2].amountMinor, 100000);
      expect(rows[2].isCredit, isTrue);
      expect(rows[3].isCredit, isFalse);
      expect(rows[3].amountMinor, 2000);
      expect(rows[4].isCredit, isFalse);
      expect(rows[5].isCredit, isFalse);
    });

    test('tabla con cargo, abono, saldo y número de operación', () {
      final table = [
        ['Fecha', 'Nro. de operación', 'Concepto', 'Cargo', 'Abono', 'Saldo'],
        ['1/10/2026', '000111', 'Compra', '45.58', '', '954.42'],
        ['2/10/2026', '000222', 'Sueldo', '0.00', '3,000.00', '3954.42'],
      ];
      final mapping = detectColumns(table)!;
      final parsed = parseStatementTable(table, mapping, fallbackCurrency: 'PEN');
      expect(parsed.rows[0].amountMinor, 4558);
      expect(parsed.rows[0].isCredit, isFalse);
      expect(parsed.rows[0].operationId, '000111');
      expect(parsed.rows[1].amountMinor, 300000);
      expect(parsed.rows[1].isCredit, isTrue);
      expect(parsed.closingBalanceMinor, 395442);
      expect(parsed.currency, 'PEN');
    });

    test('el saldo final es el de la última fecha, también si el archivo va de reciente a antiguo', () {
      final table = [
        ['Fecha', 'Concepto', 'Importe', 'Saldo'],
        ['2/10/2026', 'Sueldo', '100.00', '300.00'],
        ['1/10/2026', 'Compra', '-5.00', '200.00'],
      ];
      expect(parseStatementTable(table, detectColumns(table)!, fallbackCurrency: 'PEN').closingBalanceMinor, 30000);
    });
  });

  group('detectColumns', () {
    test('en español', () {
      final m = detectColumns([
        ['Fecha de operación', 'Glosa', 'Débito', 'Crédito', 'Saldo contable'],
      ])!;
      expect((m.date, m.description, m.debit, m.credit, m.balance, m.amount), (0, 1, 2, 3, 4, null));
    });

    test('en inglés', () {
      final m = detectColumns([
        ['Date', 'Description', 'Amount', 'Balance'],
      ])!;
      expect((m.date, m.description, m.amount, m.balance), (0, 1, 2, 3));
      final m2 = detectColumns([
        ['Posted date', 'Details', 'Withdrawal', 'Deposit'],
      ])!;
      expect((m2.date, m2.description, m2.debit, m2.credit), (0, 1, 2, 3));
    });

    test('sin cabecera reconocible no adivina', () {
      expect(
        detectColumns([
          ['a', 'b', 'c'],
          ['1/10/2026', 'Compra', '-1.00'],
        ]),
        isNull,
      );
    });
  });

  group('CSV', () {
    test('coma, comillas y cabecera de Scotiabank', () {
      const csv = 'Titular:,$_holder,\r\n'
          'Cuenta:,Cuenta Digital SBP Soles **** 1234,\r\n'
          'Fecha,Descripción,Importe S/\r\n'
          '1/10/2026,"Compra, con coma",-45.58\r\n'
          '2/10/2026,"Dice ""hola""",3000.00\r\n'
          ',,\r\n';
      final table = parseCsvTable(csv);
      final parsed = parseStatementTable(table, detectColumns(table)!, fallbackCurrency: 'PEN');
      expect(parsed.rows.map((r) => r.description), ['Compra, con coma', 'Dice "hola"']);
      expect(readStatementMeta(table).accountDigits, '1234');
    });

    test('punto y coma con decimales con coma', () {
      final table = parseCsvTable('Fecha;Concepto;Importe\n1/10/2026;Compra;-1.250,50\n');
      expect(parseStatementTable(table, detectColumns(table)!, fallbackCurrency: 'PEN').rows.single.amountMinor, 125050);
    });

    test('un archivo en Latin-1 también se lee', () async {
      final bytes = Uint8List.fromList(latin1.encode('Fecha,Descripción,Importe\n1/10/2026,Panadería,-1.00\n'));
      final loaded = await loadStatementBytes('movimientos.csv', bytes);
      expect(loaded.parse('PEN').rows.single.description, 'Panadería');
    });
  });

  group('xlsx', () {
    final oct9 = excelSerial(DateTime(2026, 10, 9));

    List<List<XCell?>> rows() => [
          [const XCell.text('Movimientos de cuenta')],
          [const XCell.text('Titular:'), const XCell.text(_holder)],
          [const XCell.inline('Cuenta:'), const XCell.inline('Cuenta Digital SBP Soles **** 1234')],
          [const XCell.text('Desde:'), XCell.date('$oct9')],
          [const XCell.text('Fecha'), const XCell.text('Descripción'), const XCell.text('Importe S/')],
          [const XCell.text('1/10/2026'), const XCell.text('Debito - compras'), const XCell.number('-45.579999999999998')],
          [XCell.date('$oct9'), const XCell.text('Punto marisko de la esquina'), const XCell.text('-12.50')],
          [XCell.number('$oct9'), const XCell.text('Serie sin estilo'), const XCell.number('3000')],
          // La descripción falta: las columnas no se corren.
          [const XCell.text('9/10/2026'), null, const XCell.number('-1.5')],
        ];

    test('lee cadenas compartidas y en línea, fechas reales y números, sin correr columnas', () {
      final table = readXlsxTable(buildXlsx(rows(), sparseRows: 500));
      // Las filas vacías del final no llegan.
      expect(table.length, 9);
      expect(table[1], ['Titular:', _holder]);
      expect(table[3][1], '9/10/2026');
      expect(table[6][1], 'Punto marisko de la esquina');
      expect(table[8], ['9/10/2026', '', '-1.50']);

      final parsed = parseStatementTable(table, detectColumns(table)!, fallbackCurrency: 'USD');
      expect(parsed.rows, hasLength(4));
      expect(parsed.rows[0].amountMinor, 4558, reason: 'el ruido de coma flotante no cambia el importe');
      expect(parsed.rows[1].date, DateTime(2026, 10, 9));
      expect(parsed.rows[1].isCredit, isFalse);
      expect(parsed.rows[2].date, DateTime(2026, 10, 9));
      expect(parsed.rows[2].amountMinor, 300000);
      expect(parsed.rows[2].isCredit, isTrue);
      expect(parsed.rows[3].amountMinor, 150);
      expect(parsed.currency, 'PEN');
      expect(readStatementMeta(table).from, DateTime(2026, 10, 9));
    });

    test('etiquetas con prefijo de espacio de nombres y hoja en otra carpeta', () {
      final table = readXlsxTable(buildXlsx(rows(), prefixed: true, sheetPath: 'sheets/hoja.xml'));
      expect(table[1], ['Titular:', _holder]);
    });

    test('el archivo .xlsx pasa por la lectura completa', () async {
      final loaded = await loadStatementBytes('movimientos.xlsx', buildXlsx(rows()));
      expect(loaded.mapping, isNotNull);
      expect(loaded.meta.holder, _holder);
      expect(loaded.parse('PEN').rows, hasLength(4));
    });

    test('un .xlsx dañado da un mensaje claro', () {
      expect(
        () => loadStatementBytes('m.xlsx', Uint8List.fromList(utf8.encode('esto no es un zip'))),
        throwsA(isA<StatementFileException>()),
      );
    });

    test('.xls antiguo pide guardarlo como .xlsx o CSV', () async {
      await expectLater(
        loadStatementBytes('m.xls', Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])),
        throwsA(isA<StatementFileException>().having((e) => e.message, 'message', 'Guárdalo como .xlsx o CSV')),
      );
    });

    test('una extensión desconocida no se intenta leer', () async {
      await expectLater(
        loadStatementBytes('m.doc', Uint8List(0)),
        throwsA(isA<StatementFileException>()),
      );
    });
  });

  group('parseStatementText (PDF con texto)', () {
    test('años implícitos con paso de diciembre a enero', () {
      const text = 'ESTADO DE CUENTA\n'
          'Titular: $_holder\n'
          'Cuenta: **** 1234 Soles\n'
          '28/12 Compra en tienda -45.58\n'
          '31/12 Yape-Otra Persona 120.00\n'
          '02/01 Debito - compras -10.00\n'
          'Total del periodo 64.42\n'
          'Página 1 de 2\n';
      final parsed = parseStatementText(text, year: 2026, fallbackCurrency: 'USD');
      expect(parsed.rows.map((r) => r.date), [DateTime(2026, 12, 28), DateTime(2026, 12, 31), DateTime(2027, 1, 2)]);
      expect(parsed.rows[0].description, 'Compra en tienda');
      expect(parsed.rows[0].amountMinor, 4558);
      expect(parsed.rows[0].isCredit, isFalse);
      expect(parsed.rows[1].isCredit, isTrue);
      expect(parsed.closingBalanceMinor, isNull);
      expect(parsed.currency, 'PEN');
    });

    test('fechas con año y con mes en letras', () {
      const text = '1/10/2026 Compra -1.00\n'
          '15 OCT Otra compra -2.00\n'
          '16-oct Tercera -3.00\n';
      final rows = parseStatementText(text, year: 2026, fallbackCurrency: 'PEN').rows;
      expect(rows.map((r) => r.date), [DateTime(2026, 10, 1), DateTime(2026, 10, 15), DateTime(2026, 10, 16)]);
    });

    test('el saldo de cada línea decide el sentido y da el saldo final', () {
      const text = 'Saldo anterior 1,000.00\n'
          '01/10 Compra 45.58 954.42\n'
          '02/10 Pago proveedor 100.00 1,054.42\n'
          'Saldo final 1,054.42\n';
      final parsed = parseStatementText(text, year: 2026, fallbackCurrency: 'PEN');
      expect(parsed.rows.map((r) => r.isCredit), [false, true]);
      expect(parsed.rows[0].amountMinor, 4558);
      expect(parsed.closingBalanceMinor, 105442);
    });

    test('una palabra que empieza como un mes no es una fecha', () {
      final rows = parseStatementText('15/10 3 Mayoristas -10.00\n2 Marisko del puerto -5.00\n', year: 2026, fallbackCurrency: 'PEN').rows;
      expect(rows.single.description, '3 Mayoristas');
    });

    test('segunda fecha y marcas de cargo y abono', () {
      const text = '01/10 02/10 Compra 45.58 DB\n'
          '03/10 03/10 Devolución 10.00 CR\n';
      final rows = parseStatementText(text, year: 2026, fallbackCurrency: 'PEN').rows;
      expect(rows[0].description, 'Compra');
      expect(rows[0].isCredit, isFalse);
      expect(rows[1].isCredit, isTrue);
    });

    test('un texto sin movimientos no da filas', () {
      expect(parseStatementText('Hola\nEste PDF no tiene nada 12\n', year: 2026, fallbackCurrency: 'PEN').rows, isEmpty);
    });

    test('un año implícito nunca queda en el futuro', () {
      final parsed = parseStatementPdfText(
        '28/12 Compra -1.00\n02/01 Otra -2.00\n',
        now: DateTime(2026, 1, 15),
        fallbackCurrency: 'PEN',
      );
      expect(parsed.rows.map((r) => r.date), [DateTime(2025, 12, 28), DateTime(2026, 1, 2)]);
    });
  });
}
