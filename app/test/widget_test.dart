import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_scatolo/models/house.dart';
import 'package:home_scatolo/screens/houses_screen.dart';
import 'package:home_scatolo/services/storage_service.dart';

/// In-memory storage service so widget tests don't depend on a real
/// (platform-specific) database, which is unreliable/unavailable in CI.
class _FakeStorageService implements StorageService {
  final List<House> _houses = <House>[];
  int _nextId = 1;
  int? _activeHouseId;

  @override
  Future<int> insertHouse(House house) async {
    final int id = _nextId++;
    _houses.add(house.copyWith(id: id));
    return id;
  }

  @override
  Future<List<House>> getHouses() async => List<House>.of(_houses);

  @override
  Future<int?> getActiveHouseId() async => _activeHouseId;

  @override
  Future<void> setActiveHouseId(int houseId) async {
    _activeHouseId = houseId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  testWidgets('HousesScreen shows AppBar with title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HousesScreen(storageService: _FakeStorageService())),
    );
    expect(find.text('Case'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('HousesScreen shows empty state message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HousesScreen(storageService: _FakeStorageService())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nessuna casa. Aggiungine una!'), findsOneWidget);
  });

  testWidgets('HousesScreen add dialog adds a house', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HousesScreen(storageService: _FakeStorageService())),
    );
    await tester.pumpAndSettle();

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

