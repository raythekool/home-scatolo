import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/container.dart' as models;
import '../models/house.dart';
import '../models/item.dart';
import '../models/room.dart';

class StorageService {
  static const String _dbName = 'home_scatolo.db';
  static const int _dbVersion = 1;

  Future<Database>? _databaseFuture;

  Future<Database> initDb() {
    return _databaseFuture ??= _openDb();
  }

  Future<Database> _openDb() async {
    final String databasesPath = await getDatabasesPath();
    final String databasePath = path.join(databasesPath, _dbName);

    return openDatabase(
      databasePath,
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
            insertedAt TEXT NOT NULL
          )
        ''');
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
}
