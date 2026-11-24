import 'package:flutter_test/flutter_test.dart';
import 'package:home_scatolo/models/container.dart' as models;
import 'package:home_scatolo/models/house.dart';
import 'package:home_scatolo/models/item.dart';
import 'package:home_scatolo/models/item_location.dart';
import 'package:home_scatolo/models/room.dart';
import 'package:home_scatolo/screens/inventory_list_screen.dart';
import 'package:home_scatolo/screens/item_detail_screen.dart';
import 'package:home_scatolo/screens/rooms_screen.dart';
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
  Future<List<House>> getHouses() async => const <House>[
        House(id: 1, name: 'Casa Vaiano'),
      ];

  @override
  Future<List<Room>> getRooms(int houseId) async =>
      houseId == 1 ? const <Room>[Room(id: 2, name: 'Cantina', houseId: 1)] : const <Room>[];

  @override
  Future<List<Item>> getItems(int containerId) async =>
      storedLocation != null && storedLocation!.item.containerId == containerId
          ? <Item>[storedLocation!.item]
          : <Item>[];

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

    final Finder saveButton = find.text('Salva modifiche');
    await tester.scrollUntilVisible(
      saveButton,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(saveButton);
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
    expect(find.text('1 risultato trovato'), findsOneWidget);
    expect(
      find.textContaining('Casa Vaiano › Cantina › Scatola Cavi'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Pulisci ricerca'));
    await tester.pumpAndSettle();
    expect(find.text('Elettronica'), findsOneWidget);
  });

  testWidgets('ItemDetailScreen shows inline validation error when name is empty',
      (WidgetTester tester) async {
    final _FakeDetailSearchStorage storage = _FakeDetailSearchStorage();
    await tester.pumpWidget(
      MaterialApp(
        home: ItemDetailScreen(itemId: '9', storageService: storage),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '');
    final Finder saveButton = find.text('Salva modifiche');
    await tester.scrollUntilVisible(
      saveButton,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(saveButton);
    await tester.pump();

    expect(find.text('Inserisci il nome dell\'oggetto.'), findsOneWidget);
    expect(storage.lastUpdated, isNull);
  });

  testWidgets('InventoryListScreen resolves QR deep link container header without title param',
      (WidgetTester tester) async {
    final _FakeDetailSearchStorage storage = _FakeDetailSearchStorage();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryListScreen(containerId: 3, storageService: storage),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scatola Cavi'), findsOneWidget);
    expect(find.text('Casa Vaiano › Cantina · scatolone'), findsOneWidget);
  });

  testWidgets('RoomsScreen shows house breadcrumb and card list',
      (WidgetTester tester) async {
    final _FakeDetailSearchStorage storage = _FakeDetailSearchStorage();
    await tester.pumpWidget(
      MaterialApp(
        home: RoomsScreen(houseId: 1, storageService: storage),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stanze'), findsOneWidget);
    expect(find.text('Casa Vaiano'), findsOneWidget);
    expect(find.text('Cantina'), findsOneWidget);
  });
}
