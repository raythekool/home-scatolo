import 'package:flutter_test/flutter_test.dart';
import 'package:home_scatolo/models/container.dart' as models;
import 'package:home_scatolo/models/item.dart';
import 'package:home_scatolo/models/item_location.dart';
import 'package:home_scatolo/screens/item_detail_screen.dart';
import 'package:home_scatolo/screens/search_screen.dart';
import 'package:home_scatolo/services/storage_service.dart';
import 'package:material_ui/material_ui.dart';

class _FakeDetailSearchStorage implements StorageService {
  ItemLocation? storedLocation = ItemLocation(
    item: Item(
      id: 9,
      name: 'Cavo HDMI',
      category: 'Elettronica',
      shortDescription: '2 metri',
      containerId: 3,
      insertedAt: DateTime.utc(2026, 11, 22),
      quantity: 2,
    ),
    houseName: 'Casa Vaiano',
    roomName: 'Cantina',
    containerName: 'Scatola Cavi',
    containerType: models.ContainerType.scatolone,
  );

  final List<models.Container> containers = const <models.Container>[
    models.Container(
      id: 3,
      name: 'Scatola Cavi',
      type: models.ContainerType.scatolone,
      roomId: 2,
    ),
    models.Container(
      id: 4,
      name: 'Armadio Studio',
      type: models.ContainerType.armadio,
      roomId: 2,
    ),
  ];

  Item? lastUpdated;
  int? lastDeletedId;

  @override
  Future<ItemLocation?> getItemLocation(int itemId) async {
    if (storedLocation?.item.id == itemId) return storedLocation;
    return null;
  }

  @override
  Future<List<models.Container>> getAllContainers() async => containers;

  @override
  Future<void> updateItem(Item item) async {
    lastUpdated = item;
    if (storedLocation != null) {
      storedLocation = ItemLocation(
        item: item,
        houseName: storedLocation!.houseName,
        roomName: storedLocation!.roomName,
        containerName: storedLocation!.containerName,
        containerType: storedLocation!.containerType,
      );
    }
  }

  @override
  Future<void> deleteItem(int itemId) async {
    lastDeletedId = itemId;
    storedLocation = null;
  }

  @override
  Future<List<ItemLocation>> searchItemsWithLocation(String query) async {
    final ItemLocation? current = storedLocation;
    if (current == null || query.trim().isEmpty) return <ItemLocation>[];
    if (current.item.name.toLowerCase().contains(query.trim().toLowerCase())) {
      return <ItemLocation>[current];
    }
    return <ItemLocation>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  testWidgets('ItemDetailScreen loads item location, increments quantity, and saves',
      (WidgetTester tester) async {
    final _FakeDetailSearchStorage storage = _FakeDetailSearchStorage();
    await tester.pumpWidget(
      MaterialApp(
        home: ItemDetailScreen(itemId: '9', storageService: storage),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Casa Vaiano › Cantina › Scatola Cavi'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byTooltip('Aumenta quantità'));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.text('Salva modifiche'));
    await tester.pumpAndSettle();

    expect(storage.lastUpdated?.quantity, 3);
  });

  testWidgets('SearchScreen shows full location path after debounced search',
      (WidgetTester tester) async {
    final _FakeDetailSearchStorage storage = _FakeDetailSearchStorage();
    await tester.pumpWidget(
      MaterialApp(
        home: SearchScreen(storageService: storage),
      ),
    );

    await tester.enterText(find.byType(TextField), 'HDMI');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Cavo HDMI'), findsOneWidget);
    expect(
      find.textContaining('Casa Vaiano › Cantina › Scatola Cavi'),
      findsOneWidget,
    );
  });
}
