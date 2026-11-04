import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/parse_statement.dart';
import '../domain/statement.dart';
import 'pdf_text_reader.dart';
import 'xlsx_table_reader.dart';

/// El archivo no se puede leer; [message] se muestra tal cual.
class StatementFileException implements Exception {
  const StatementFileException(this.message);
  final String message;
}

const kOldExcelMessage = 'Guárdalo como .xlsx o CSV';
const kImageOnlyPdfMessage =
    'Este PDF tiene solo imágenes, sin texto que leer. Descarga el estado de cuenta en Excel (.xlsx) o CSV y vuelve a intentarlo.';
const kUnreadableMessage = 'No se pudo leer este archivo. Prueba con el estado de cuenta en Excel (.xlsx) o CSV.';

/// Un archivo elegido. Su copia temporal se borra con [discard] al terminar de leerlo.
abstract interface class PickedStatement {
  String get name;
  String? get path;
  Future<Uint8List> readBytes();
  Future<void> discard();
}

abstract interface class StatementFilePicker {
  /// null si el usuario cancela.
  Future<PickedStatement?> pick();
}

class _PlatformPicked implements PickedStatement {
  _PlatformPicked(this._file);
  final PlatformFile _file;

  @override
  String get name => _file.name;
  @override
  String? get path => _file.path;
  @override
  Future<Uint8List> readBytes() => _file.readAsBytes();

  @override
  Future<void> discard() async {
    // file_picker copia el archivo a la carpeta de la app; solo esa copia se borra,
    // nunca un original fuera de ella.
    try {
      final own = _file.path;
      if (own != null && (Platform.isAndroid || Platform.isIOS)) {
        final cache = await getTemporaryDirectory();
        final sandbox = Platform.isIOS ? cache.parent.parent : cache.parent;
        if (own.startsWith(sandbox.path)) await File(own).delete();
      }
    } catch (_) {}
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {}
  }
}

class _PlatformStatementPicker implements StatementFilePicker {
  const _PlatformStatementPicker();

  @override
  Future<PickedStatement?> pick() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf', 'xlsx', 'csv', 'xls']);
    return file == null ? null : _PlatformPicked(file);
  }
}

final statementFilePickerProvider = Provider<StatementFilePicker>((ref) => const _PlatformStatementPicker());

/// Lo leído de un archivo. Queda en memoria mientras se revisa; no se guarda.
class LoadedStatement {
  const LoadedStatement({required this.text, required this.meta, required this.parse, this.table, this.mapping});

  /// Texto para la IA (solo si el usuario la activa).
  final String text;
  final StatementMeta meta;

  /// La tabla leída, para elegir columnas si no se reconocieron ([mapping] null).
  final List<List<String>>? table;
  final ColumnMapping? mapping;

  /// Filas en la moneda indicada, si el archivo no dice la suya.
  final ParsedStatement Function(String fallbackCurrency) parse;
}

LoadedStatement _fromTable(List<List<String>> table) {
  final mapping = detectColumns(table);
  return LoadedStatement(
    text: [for (final r in table) r.join(' | ')].join('\n'),
    meta: readStatementMeta(table),
    table: table,
    mapping: mapping,
    parse: (currency) => mapping == null ? const ParsedStatement(rows: []) : parseStatementTable(table, mapping, fallbackCurrency: currency),
  );
}

String _decodeText(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    final units = bytes.buffer.asUint16List(bytes.offsetInBytes + 2, (bytes.length - 2) ~/ 2);
    return String.fromCharCodes(units);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

bool _startsWith(Uint8List bytes, List<int> magic) {
  if (bytes.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic[i]) return false;
  }
  return true;
}

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
}

bool isPdfName(String name) => _extension(name) == 'pdf';

const _zip = [0x50, 0x4B];

/// Lee un CSV o un Excel. Un .xls que en realidad es un .xlsx también vale; los
/// grandes se abren en otro hilo para no congelar la pantalla.
Future<LoadedStatement> loadStatementBytes(String name, Uint8List bytes) async {
  final ext = _extension(name);
  if (ext == 'csv' || ext == 'txt') return _fromTable(parseCsvTable(_decodeText(bytes)));
  if (ext != 'xlsx' && ext != 'xls') throw const StatementFileException(kUnreadableMessage);
  if (!_startsWith(bytes, _zip)) {
    throw StatementFileException(ext == 'xls' || bytes.length >= 4 && bytes[0] == 0xD0 ? kOldExcelMessage : kUnreadableMessage);
  }
  try {
    final table = bytes.length > 256 * 1024 ? await compute(readXlsxTable, bytes) : readXlsxTable(bytes);
    return _fromTable(table);
  } on XlsxReadException {
    throw const StatementFileException(kUnreadableMessage);
  }
}

/// Lee el texto de un PDF. Lanza [PdfPasswordRequired] o [PdfWrongPassword] para
/// que se pida la contraseña, y un mensaje claro si no tiene texto.
Future<LoadedStatement> loadStatementPdf(PickedStatement file, PdfTextReader reader, {String? password, required DateTime now}) async {
  final path = file.path;
  if (path == null) throw const StatementFileException(kUnreadableMessage);
  final String text;
  try {
    text = await reader.read(path, password: password);
  } on PdfReadFailed {
    throw const StatementFileException(kUnreadableMessage);
  }
  if (text.trim().isEmpty) throw const StatementFileException(kImageOnlyPdfMessage);
  return LoadedStatement(
    text: text,
    meta: readStatementMetaText(text),
    parse: (currency) => parseStatementPdfText(text, now: now, fallbackCurrency: currency),
  );
}
