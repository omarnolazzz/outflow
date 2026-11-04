import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Una celda de la hoja de prueba.
class XCell {
  const XCell.text(this.value) : kind = 's';
  const XCell.inline(this.value) : kind = 'inline';
  const XCell.number(this.value) : kind = 'n';

  /// Número de serie con el estilo de fecha de la hoja.
  const XCell.date(this.value) : kind = 'date';
  final String value;
  final String kind;
}

String _column(int i) => String.fromCharCode(65 + i);

/// Un .xlsx con la estructura que escribe Excel: cadenas compartidas, estilos y
/// celdas con posición (las vacías no aparecen). [sparseRows] añade filas sin
/// contenido al final, como las que deja el banco.
Uint8List buildXlsx(List<List<XCell?>> rows, {int sparseRows = 0, bool prefixed = false, String sheetPath = 'worksheets/sheet1.xml'}) {
  final p = prefixed ? 'x:' : '';
  final ns = prefixed ? 'xmlns:x' : 'xmlns';
  final shared = <String>[];
  final sheet = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<${p}worksheet $ns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><${p}sheetData>');
  for (var r = 0; r < rows.length; r++) {
    sheet.write('<${p}row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final cell = rows[r][c];
      if (cell == null) continue;
      final ref = '${_column(c)}${r + 1}';
      switch (cell.kind) {
        case 's':
          shared.add(cell.value);
          sheet.write('<${p}c r="$ref" t="s"><${p}v>${shared.length - 1}</${p}v></${p}c>');
        case 'inline':
          sheet.write('<${p}c r="$ref" t="inlineStr"><${p}is><${p}t>${cell.value}</${p}t></${p}is></${p}c>');
        case 'date':
          sheet.write('<${p}c r="$ref" s="1"><${p}v>${cell.value}</${p}v></${p}c>');
        default:
          sheet.write('<${p}c r="$ref"><${p}v>${cell.value}</${p}v></${p}c>');
      }
    }
    sheet.write('</${p}row>');
  }
  for (var i = 0; i < sparseRows; i++) {
    sheet.write('<${p}row r="${rows.length + i + 1}"><${p}c r="A${rows.length + i + 1}" s="1"/></${p}row>');
  }
  sheet.write('</${p}sheetData></${p}worksheet>');

  final strings = StringBuffer('<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
  for (final s in shared) {
    // Una cadena con formato llega partida en trozos.
    final mid = s.length ~/ 2;
    strings.write(s.length > 12
        ? '<si><r><t xml:space="preserve">${s.substring(0, mid)}</t></r><r><rPr><b/></rPr><t xml:space="preserve">${s.substring(mid)}</t></r></si>'
        : '<si><t>$s</t></si>');
  }
  strings.write('</sst>');

  const styles = '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<numFmts count="1"><numFmt numFmtId="170" formatCode="d/m/yyyy;@"/></numFmts>'
      '<cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="170" applyNumberFormat="1"/></cellXfs></styleSheet>';
  const workbook = '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="Movimientos" sheetId="1" r:id="rId1"/></sheets></workbook>';
  final rels = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="$sheetPath"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';

  final archive = Archive()
    ..add(ArchiveFile.string('[Content_Types].xml', '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>'))
    ..add(ArchiveFile.string('xl/workbook.xml', workbook))
    ..add(ArchiveFile.string('xl/_rels/workbook.xml.rels', rels))
    ..add(ArchiveFile.string('xl/styles.xml', styles))
    ..add(ArchiveFile.string('xl/sharedStrings.xml', strings.toString()))
    ..add(ArchiveFile.string('xl/$sheetPath', sheet.toString()));
  return ZipEncoder().encodeBytes(archive);
}

/// Serie de Excel de una fecha (sistema 1900).
int excelSerial(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1899, 12, 30)).inDays;
