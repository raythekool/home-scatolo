import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_scatolo/screens/houses_screen.dart';

void main() {
  testWidgets('HousesScreen shows AppBar with title', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HousesScreen()));
    expect(find.text('Case'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('HousesScreen shows empty state message', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HousesScreen()));
    expect(find.text('Nessuna casa. Aggiungine una!'), findsOneWidget);
  });

  testWidgets('HousesScreen add dialog adds a house', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HousesScreen()));

    // Open the add dialog
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('Nuova casa'), findsOneWidget);

    // Type the house name and confirm
    await tester.enterText(find.byType(TextField), 'Villa Rossi');
    await tester.tap(find.text('Aggiungi'));
    await tester.pumpAndSettle();

    // The house should now appear in the list
    expect(find.text('Villa Rossi'), findsOneWidget);
    // Empty state message should be gone
    expect(find.text('Nessuna casa. Aggiungine una!'), findsNothing);
  });
}
