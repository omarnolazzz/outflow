import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../domain/parse_statement.dart' show detectColumns;

/// El .xlsx no se pudo leer.
class XlsxReadException implements Exception {
  const XlsxReadException();
}

/// Formatos de fecha integrados de Excel. El resto se reconoce por su código.
bool _isDateFormatId(int id) => (id >= 14 && id <= 22) || (id >= 27 && id <= 36) || (id >= 45 && id <= 47) || (id >= 50 && id <= 58);

/// Un código de formato es de fecha si tiene d, m o y fuera de corchetes y comillas.
bool _isDateFormatCode(String code) {
  final bare = code.replaceAll(RegExp(r'\[[^\]]*\]|"[^"]*"|\\.'), '').toLowerCase();
  if (bare.contains('general')) return false;
  return RegExp(r'[dmy]').hasMatch(bare);
}

XmlDocument? _xml(Archive archive, String path) {
  final file = archive.findFile(path);
  if (file == null) return null;
  return XmlDocument.parse(utf8.decode(file.content, allowMalformed: true));
}

Iterable<XmlElement> _all(XmlNode node, String name) => node.findAllElements(name, namespaceUri: '*');

/// Texto de una cadena: puede venir en trozos con formato (`<r>`), sin la fonética.
String _stringOf(XmlElement si) {
  final b = StringBuffer();
  void visit(XmlElement e) {
    for (final child in e.childElements) {
      if (child.name.local == 't') {
        b.write(child.innerText);
      } else if (child.name.local == 'r') {
        visit(child);
      }
    }
  }

  visit(si);
  return b.toString();
}

int _columnOf(String ref, int fallback) {
  var column = 0;
  var any = false;
  for (final unit in ref.toUpperCase().codeUnits) {
    if (unit < 65 || unit > 90) break;
    column = column * 26 + unit - 64;
    any = true;
  }
  return any ? column - 1 : fallback;
}

String _dateText(num serial, bool date1904) {
  final d = DateTime(date1904 ? 1904 : 1899, date1904 ? 1 : 12, (date1904 ? 1 : 30) + serial.floor());
  return '${d.day}/${d.month}/${d.year}';
}

/// Los números se dejan con dos decimales como mucho: Excel guarda -45.58 como
/// -45.579999999999998, y un entero sin decimales puede ser una fecha en serie.
String _numberText(String raw) {
  final n = double.tryParse(raw);
  if (n == null) return raw;
  if (n == n.roundToDouble()) return n.toStringAsFixed(0);
  return n.toStringAsFixed(2);
}

List<List<String>> _readSheet(XmlDocument sheet, List<String> shared, Set<int> dateStyles, bool date1904) {
  final table = <List<String>>[];
  for (final row in _all(sheet, 'row')) {
    final cells = <String>[];
    var next = 0;
    var hasContent = false;
    for (final c in row.childElements.where((e) => e.name.local == 'c')) {
      final column = _columnOf(c.getAttribute('r') ?? '', next);
      next = column + 1;
      final type = c.getAttribute('t') ?? 'n';
      final style = int.tryParse(c.getAttribute('s') ?? '') ?? 0;
      final raw = c.childElements.where((e) => e.name.local == 'v').firstOrNull?.innerText ?? '';
      final value = switch (type) {
        's' => () {
            final i = int.tryParse(raw);
            return i != null && i >= 0 && i < shared.length ? shared[i] : '';
          }(),
        'inlineStr' => c.childElements.where((e) => e.name.local == 'is').map(_stringOf).firstOrNull ?? '',
        'str' || 'd' => raw,
        'b' || 'e' => '',
        _ when raw.isEmpty => '',
        _ when dateStyles.contains(style) && num.tryParse(raw) != null => _dateText(num.parse(raw), date1904),
        _ => _numberText(raw),
      };
      if (value.trim().isEmpty) continue;
      while (cells.length < column) {
        cells.add('');
      }
      cells.add(value.trim());
      hasContent = true;
    }
    // Las hojas del banco traen miles de filas vacías al final: no se guardan.
    if (hasContent) table.add(cells);
  }
  return table;
}

/// Lee la hoja de movimientos de un .xlsx: las celdas como texto, las fechas reales
/// como `d/m/yyyy`, sin las filas vacías. Va directo sobre el ZIP y el XML porque
/// `spreadsheet_decoder` y `excel` exigen `archive` 3 y `image` exige la 4.
/// Lanza [XlsxReadException] si no es un .xlsx.
List<List<String>> readXlsxTable(Uint8List bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final workbook = _xml(archive, 'xl/workbook.xml');
    if (workbook == null) throw const XlsxReadException();

    final shared = <String>[
      for (final si in _all(_xml(archive, 'xl/sharedStrings.xml') ?? XmlDocument(), 'si')) _stringOf(si),
    ];

    final dateStyles = <int>{};
    final styles = _xml(archive, 'xl/styles.xml');
    if (styles != null) {
      final codes = {
        for (final f in _all(styles, 'numFmt')) int.tryParse(f.getAttribute('numFmtId') ?? ''): f.getAttribute('formatCode') ?? '',
      };
      final xfs = _all(styles, 'cellXfs').firstOrNull?.childElements.where((e) => e.name.local == 'xf').toList() ?? const <XmlElement>[];
      for (var i = 0; i < xfs.length; i++) {
        final id = int.tryParse(xfs[i].getAttribute('numFmtId') ?? '') ?? 0;
        final code = codes[id];
        if (code != null ? _isDateFormatCode(code) : _isDateFormatId(id)) dateStyles.add(i);
      }
    }

    final properties = _all(workbook, 'workbookPr').firstOrNull;
    final flag = properties?.getAttribute('date1904');
    final date1904 = flag == '1' || flag == 'true';

    final rels = _xml(archive, 'xl/_rels/workbook.xml.rels');
    final targets = <String, String>{
      if (rels != null)
        for (final r in _all(rels, 'Relationship')) r.getAttribute('Id') ?? '': r.getAttribute('Target') ?? '',
    };

    final tables = <List<List<String>>>[];
    for (final s in _all(workbook, 'sheet')) {
      final rid = s.attributes.where((a) => a.name.local == 'id').firstOrNull?.value;
      final target = targets[rid];
      if (target == null) continue;
      final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      final doc = _xml(archive, path);
      if (doc == null) continue;
      final table = _readSheet(doc, shared, dateStyles, date1904);
      // La primera hoja con movimientos reconocibles; si ninguna, la primera con datos.
      if (detectColumns(table) != null) return table;
      if (table.isNotEmpty) tables.add(table);
    }
    if (tables.isEmpty && targets.isEmpty) throw const XlsxReadException();
    return tables.firstOrNull ?? const [];
  } on XlsxReadException {
    rethrow;
  } catch (_) {
    // El contenido del archivo no se registra.
    throw const XlsxReadException();
  }
}
