import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/capture/data/capture_inbox.dart';

String _line(String text) => '${jsonEncode({
      'sourceKey': 'com.x',
      'sourceLabel': 'X',
      'text': text,
      'receivedAt': '2026-11-03T10:00:00.000Z',
    })}\n';

void main() {
  late Directory dir;
  late CaptureInbox inbox;
  File file(String name) => File('${dir.path}/$name');
  List<String> merges() => dir.listSync().map((e) => e.uri.pathSegments.last).where((n) => n.startsWith('capture_inbox.merge.')).toList();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('inbox');
    inbox = CaptureInbox(directory: () async => dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('con .processing viejo, une la bandeja sin perder nada', () async {
    await file('capture_inbox.processing').writeAsString(_line('uno'));
    await file('capture_inbox.jsonl').writeAsString(_line('dos'));
    final events = await inbox.pending();
    expect(events.map((e) => e.text), ['uno', 'dos']);
    expect(file('capture_inbox.jsonl').existsSync(), isFalse);
    expect(merges(), isEmpty);
    await inbox.commit();
    expect(file('capture_inbox.processing').existsSync(), isFalse);
  });

  test('una línea añadida tras apartar la bandeja sobrevive al commit', () async {
    await file('capture_inbox.jsonl').writeAsString(_line('uno'));
    final events = await inbox.pending();
    expect(events.map((e) => e.text), ['uno']);
    // El servicio tenía el archivo abierto a través del rename y escribe tarde.
    await file('capture_inbox.processing').writeAsString(_line('tarde'), mode: FileMode.append);
    await inbox.commit();
    final next = await inbox.pending();
    expect(next.map((e) => e.text), ['tarde']);
    await inbox.commit();
    expect(file('capture_inbox.processing').existsSync(), isFalse);
  });

  test('pending recoge restos capture_inbox.merge.* tras un corte', () async {
    await file('capture_inbox.merge.123').writeAsString(_line('resto'));
    final events = await inbox.pending();
    expect(events.map((e) => e.text), ['resto']);
    expect(merges(), isEmpty);
    await inbox.commit();
  });

  test('clear borra también los restos de unión', () async {
    await file('capture_inbox.merge.123').writeAsString(_line('resto'));
    await file('capture_inbox.processing').writeAsString(_line('a'));
    await file('capture_inbox.jsonl').writeAsString(_line('b'));
    await inbox.clear();
    expect(dir.listSync(), isEmpty);
  });
}
