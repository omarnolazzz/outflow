import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:outflow/features/friends/domain/shared_expense.dart';
import 'package:outflow/features/friends/presentation/friends_format.dart';

void main() {
  testWidgets('con foto de Google se pinta la imagen', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PersonAvatar(Person(uid: 'a', name: 'Ana', email: 'ana@x.com', photoUrl: 'https://x/ana.jpg')),
    ));
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, 'https://x/ana.jpg');
  });

  testWidgets('sin foto se ve la inicial', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PersonAvatar(Person(uid: 'a', name: 'Ana', email: 'ana@x.com'))));
    expect(find.byType(Image), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });
}
