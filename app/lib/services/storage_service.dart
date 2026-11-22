import 'package:sqflite/sqflite.dart';

import '../models/container.dart' as models;
import '../models/house.dart';
import '../models/item.dart';
import '../models/item_location.dart';
import '../models/room.dart';
import 'database_opener.dart' if (dart.library.html) 'database_opener_web.dart';

class StorageService {
  static const String _dbName = 'home_scatolo.db';
  static const int _dbVersion = 2;

  Future<Database>? _databaseFuture;

  Future<Database> initDb() {
    return _databaseFuture ??= _openDb();
  }

  Future<Database> _openDb() async {
    return openHomeScatoloDatabase(
      dbName: _dbName,
      version: _dbVersion,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE houses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE rooms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            houseId INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE containers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            roomId INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            shortDescription TEXT NOT NULL,
            photoPath TEXT,
            containerId INTEGER NOT NULL,
            insertedAt TEXT NOT NULL,
            quantity INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE TABLE app_state (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE items ADD COLUMN quantity INTEGER NOT NULL DEFAULT 1',
          );
        }
      },
    );
  }

  Future<int> insertHouse(House house) async {
    final Database db = await initDb();
    return db.insert('houses', house.toMap());
  }

  Future<List<House>> getHouses() async {
    final Database db = await initDb();
    final List<Map<String, dynamic>> result = await db.query('houses');
    return result.map(House.fromMap).toList();
  }

  Future<int> insertRoom(Room room) async {
    final Database db = await initDb();
    return db.insert('rooms', room.toMap());
  }

  Future<List<Room>> getRooms(int houseId) async {
    final Database db = await initDb();
    final List<Map<String, dynamic>> result = await db.query(
      'rooms',
      where: 'houseId = ?',
      whereArgs: <Object?>[houseId],
    );
    return result.map(Room.fromMap).toList();
  }

  Future<int> insertContainer(models.Container container) async {
    final Database db = await initDb();
    return db.insert('containers', container.toMap());
  }

  Future<List<models.Container>> getContainers(int roomId) async {
    final Database db = await initDb();
    final List<Map<String, dynamic>> result = await db.query(
      'containers',
      where: 'roomId = ?',
      whereArgs: <Object?>[roomId],
    );
    return result.map(models.Container.fromMap).toList();
  }

  Future<List<models.Container>> getAllContainers() async {
    final Database db = await initDb();
    final List<Map<String, dynamic>> result = await db.query(
      'containers',
      orderBy: 'name ASC',
    );
    return result.map(models.Container.fromMap).toList();
  }

  Future<int> getOrCreateQuickScanContainer() async {
    final Database db = await initDb();
    return db.transaction((Transaction transaction) async {
      final List<Map<String, dynamic>> houses = await transaction.query(
        'houses',
        orderBy: 'id ASC',
        limit: 1,
      );
      final int houseId;
      if (houses.isEmpty) {
        houseId = await transaction.insert(
          'houses',
          const <String, Object?>{'name': 'La mia casa'},
        );
        await transaction.insert(
          'app_state',
          <String, Object?>{
            'key': 'activeHouseId',
            'value': houseId.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        houseId = houses.single['id'] as int;
      }

      final List<Map<String, dynamic>> rooms = await transaction.query(
        'rooms',
        where: 'houseId = ?',
        whereArgs: <Object?>[houseId],
        orderBy: 'id ASC',
        limit: 1,
      );
      final int roomId = rooms.isEmpty
          ? await transaction.insert(
              'rooms',
              <String, Object?>{'name': 'Ingresso', 'houseId': houseId},
            )
          : rooms.single['id'] as int;

      final List<Map<String, dynamic>> containers = await transaction.query(
        'containers',
        where: 'roomId = ?',
        whereArgs: <Object?>[roomId],
        orderBy: 'id ASC',
        limit: 1,
      );
      if (containers.isNotEmpty) return containers.single['id'] as int;

      return transaction.insert(
        'containers',
        <String, Object?>{
          'name': 'Da ordinare',
          'type': models.ContainerType.scatolone.toValue(),
          'roomId': roomId,
        },
      );
    });
  }

  Future<int> insertItem(Item item) async {
    final Database db = await initDb();
    return db.insert('items', item.toMap());
  }

  Future<List<Item>> getItems(int containerId) async {
    final Database db = await initDb();
    final List<Map<String, dynamic>> result = await db.query(
      'items',
      where: 'containerId = ?',
      whereArgs: <Object?>[containerId],
    );
    return result.map(Item.fromMap).toList();
  }

  Future<List<Item>> getAllItems() async {
    final Database db = await initDb();
    final List<Map<String, dynamic>> result = await db.query(
      'items',
      orderBy: 'insertedAt DESC',
    );
    return result.map(Item.fromMap).toList();
  }

  Future<void> incrementItemQuantity({
    required int itemId,
    required int amount,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be positive');
    }

    final Database db = await initDb();
    await db.transaction((Transaction transaction) async {
      final int updated = await transaction.rawUpdate(
        'UPDATE items SET quantity = quantity + ? WHERE id = ?',
        <Object?>[amount, itemId],
      );
      if (updated != 1) {
        throw StateError('Item $itemId does not exist');
      }
    });
  }

  Future<int?> getActiveHouseId() async {
    final Database db = await initDb();
    final List<Map<String, dynamic>> result = await db.query(
      'app_state',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>['activeHouseId'],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return int.tryParse(result.single['value'] as String);
  }

  Future<void> setActiveHouseId(int houseId) async {
    final Database db = await initDb();
    await db.insert(
      'app_state',
      <String, Object?>{
        'key': 'activeHouseId',
        'value': houseId.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Item>> searchItems(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return <Item>[];

    final Database db = await initDb();
    final String pattern = '%${trimmed.toLowerCase()}%';
    final List<Map<String, dynamic>> result = await db.query(
      'items',
      where: '''
        lower(name) LIKE ?
        OR lower(category) LIKE ?
        OR lower(shortDescription) LIKE ?
      ''',
      whereArgs: <Object?>[pattern, pattern, pattern],
      orderBy: 'insertedAt DESC',
    );
    return result.map(Item.fromMap).toList();
  }

  Future<List<ItemLocation>> searchItemsWithLocation(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return <ItemLocation>[];

    final Database db = await initDb();
    final String pattern = '%${trimmed.toLowerCase()}%';
    final List<Map<String, dynamic>> result = await db.rawQuery(
      '''
      SELECT
        i.id, i.name, i.category, i.shortDescription, i.photoPath,
        i.containerId, i.insertedAt, i.quantity,
        c.name AS containerName, c.type AS containerType,
        r.name AS roomName,
        h.name AS houseName
      FROM items i
      JOIN containers c ON c.id = i.containerId
      JOIN rooms r ON r.id = c.roomId
      JOIN houses h ON h.id = r.houseId
      WHERE lower(i.name) LIKE ?
         OR lower(i.category) LIKE ?
         OR lower(i.shortDescription) LIKE ?
         OR lower(c.name) LIKE ?
         OR lower(r.name) LIKE ?
      ORDER BY i.insertedAt DESC
      ''',
      <Object?>[pattern, pattern, pattern, pattern, pattern],
    );
    return result.map(ItemLocation.fromMap).toList();
  }

  Future<ItemLocation?> getItemLocation(int itemId) async {
    final Database db = await initDb();
    final List<Map<String, dynamic>> result = await db.rawQuery(
      '''
      SELECT
        i.id, i.name, i.category, i.shortDescription, i.photoPath,
        i.containerId, i.insertedAt, i.quantity,
        c.name AS containerName, c.type AS containerType,
        r.name AS roomName,
        h.name AS houseName
      FROM items i
      JOIN containers c ON c.id = i.containerId
      JOIN rooms r ON r.id = c.roomId
      JOIN houses h ON h.id = r.houseId
      WHERE i.id = ?
      LIMIT 1
      ''',
      <Object?>[itemId],
    );
    if (result.isEmpty) return null;
    return ItemLocation.fromMap(result.single);
  }

  Future<void> updateItem(Item item) async {
    final int? itemId = item.id;
    if (itemId == null) {
      throw ArgumentError('Cannot update an item without id');
    }
    final Database db = await initDb();
    final int updated = await db.update(
      'items',
      <String, Object?>{
        'name': item.name,
        'category': item.category,
        'shortDescription': item.shortDescription,
        'photoPath': item.photoPath,
        'containerId': item.containerId,
        'quantity': item.quantity,
      },
      where: 'id = ?',
      whereArgs: <Object?>[itemId],
    );
    if (updated != 1) {
      throw StateError('Item $itemId does not exist');
    }
  }

  Future<void> deleteItem(int itemId) async {
    final Database db = await initDb();
    final int deleted = await db.delete(
      'items',
      where: 'id = ?',
      whereArgs: <Object?>[itemId],
    );
    if (deleted != 1) {
      throw StateError('Item $itemId does not exist');
    }
  }
}
