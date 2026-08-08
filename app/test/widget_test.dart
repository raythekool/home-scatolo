import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_scatolo/screens/houses_screen.dart';

void main() {
  testWidgets('HousesScreen shows AppBar with title', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HousesScreen()));
    expect(find.text('Case'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
