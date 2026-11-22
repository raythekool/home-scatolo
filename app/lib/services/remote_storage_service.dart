import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart' show Database;

import '../models/container.dart' as models;
import '../models/house.dart';
import '../models/item.dart';
import '../models/item_location.dart';
import '../models/room.dart';
import 'storage_service.dart';

const String _defaultBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000',
);
const String _defaultApiToken = String.fromEnvironment('API_TOKEN');
const Duration _requestTimeout = Duration(seconds: 30);

class RemoteStorageService implements StorageService {
  RemoteStorageService({
    String? baseUrl,
    String? apiToken,
    http.Client? client,
  })  : baseUrl = _normalizeBaseUrl(baseUrl ?? _defaultBaseUrl),
        apiToken = (apiToken ?? _defaultApiToken).trim(),
        _client = client ?? http.Client();

  final String baseUrl;
  final String apiToken;
  final http.Client _client;

  static String _normalizeBaseUrl(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers({bool jsonBody = false}) {
    return <String, String>{
      if (jsonBody) 'Content-Type': 'application/json',
      if (apiToken.isNotEmpty) 'Authorization': 'Bearer $apiToken',
    };
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final http.Response response = await _client
        .get(_uri(path), headers: _headers())
        .timeout(_requestTimeout);
    return _decodeObjectResponse(response);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final http.Response response = await _client
        .post(
          _uri(path),
          headers: _headers(jsonBody: true),
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout);
    return _decodeObjectResponse(response);
  }

  Future<Map<String, dynamic>> _putJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final http.Response response = await _client
        .put(
          _uri(path),
          headers: _headers(jsonBody: true),
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout);
    return _decodeObjectResponse(response);
  }

  Future<Map<String, dynamic>> _patchJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final http.Response response = await _client
        .patch(
          _uri(path),
          headers: _headers(jsonBody: true),
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout);
    return _decodeObjectResponse(response);
  }

  Future<void> _delete(String path) async {
    final http.Response response = await _client
        .delete(_uri(path), headers: _headers())
        .timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Inventory request failed: ${response.statusCode}');
    }
  }

  Map<String, dynamic> _decodeObjectResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Inventory request failed: ${response.statusCode}');
    }
    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Invalid inventory response format');
    }
    return Map<String, dynamic>.from(decoded);
  }

  List<Map<String, dynamic>> _extractList(
    Map<String, dynamic> payload,
    String key,
  ) {
    final dynamic raw = payload[key];
    if (raw is! List) {
      throw Exception('Invalid inventory list for "$key"');
    }
    return raw.map<Map<String, dynamic>>((dynamic entry) {
      if (entry is! Map) {
        throw Exception('Invalid entry in "$key"');
      }
      return Map<String, dynamic>.from(entry);
    }).toList();
  }

  @override
  Future<Database> initDb() {
    throw UnsupportedError(
      'RemoteStorageService does not use a local SQLite database.',
    );
  }

  @override
  Future<int> insertHouse(House house) async {
    final Map<String, dynamic> created = await _postJson(
      '/api/houses',
      <String, dynamic>{'name': house.name},
    );
    return created['id'] as int;
  }

  @override
  Future<List<House>> getHouses() async {
    final Map<String, dynamic> payload = await _getJson('/api/houses');
    return _extractList(payload, 'houses').map(House.fromMap).toList();
  }

  @override
  Future<int> insertRoom(Room room) async {
    final Map<String, dynamic> created = await _postJson(
      '/api/rooms',
      <String, dynamic>{'name': room.name, 'houseId': room.houseId},
    );
    return created['id'] as int;
  }

  @override
  Future<List<Room>> getRooms(int houseId) async {
    final Map<String, dynamic> payload =
        await _getJson('/api/houses/$houseId/rooms');
    return _extractList(payload, 'rooms').map(Room.fromMap).toList();
  }

  @override
  Future<int> insertContainer(models.Container container) async {
    final Map<String, dynamic> created = await _postJson(
      '/api/containers',
      <String, dynamic>{
        'name': container.name,
        'type': container.type.toValue(),
        'roomId': container.roomId,
      },
    );
    return created['id'] as int;
  }

  @override
  Future<List<models.Container>> getContainers(int roomId) async {
    final Map<String, dynamic> payload =
        await _getJson('/api/rooms/$roomId/containers');
    return _extractList(payload, 'containers')
        .map(models.Container.fromMap)
        .toList();
  }

  @override
  Future<List<models.Container>> getAllContainers() async {
    final Map<String, dynamic> payload = await _getJson('/api/containers');
    return _extractList(payload, 'containers')
        .map(models.Container.fromMap)
        .toList();
  }

  @override
  Future<int> getOrCreateQuickScanContainer() async {
    final Map<String, dynamic> result = await _postJson(
      '/api/quick-scan-container',
      const <String, dynamic>{},
    );
    return result['containerId'] as int;
  }

  @override
  Future<int> insertItem(Item item) async {
    final Map<String, dynamic> created = await _postJson(
      '/api/items',
      <String, dynamic>{
        'name': item.name,
        'category': item.category,
        'shortDescription': item.shortDescription,
        'photoPath': item.photoPath,
        'containerId': item.containerId,
        'insertedAt': item.insertedAt.toIso8601String(),
        'quantity': item.quantity,
      },
    );
    return created['id'] as int;
  }

  @override
  Future<List<Item>> getItems(int containerId) async {
    final Map<String, dynamic> payload =
        await _getJson('/api/containers/$containerId/items');
    return _extractList(payload, 'items').map(Item.fromMap).toList();
  }

  @override
  Future<List<Item>> getAllItems() async {
    final Map<String, dynamic> payload = await _getJson('/api/items');
    return _extractList(payload, 'items').map(Item.fromMap).toList();
  }

  @override
  Future<void> incrementItemQuantity({
    required int itemId,
    required int amount,
  }) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be positive');
    }
    await _postJson(
      '/api/items/$itemId/increment',
      <String, dynamic>{'amount': amount},
    );
  }

  @override
  Future<int?> getActiveHouseId() async {
    final Map<String, dynamic> payload =
        await _getJson('/api/state/activeHouseId');
    final dynamic value = payload['value'];
    if (value is! String) return null;
    return int.tryParse(value);
  }

  @override
  Future<void> setActiveHouseId(int houseId) async {
    await _putJson(
      '/api/state/activeHouseId',
      <String, dynamic>{'value': houseId.toString()},
    );
  }

  @override
  Future<List<Item>> searchItems(String query) async {
    final List<ItemLocation> matches = await searchItemsWithLocation(query);
    return matches.map((ItemLocation loc) => loc.item).toList();
  }

  @override
  Future<List<ItemLocation>> searchItemsWithLocation(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return <ItemLocation>[];
    final String encoded = Uri.encodeQueryComponent(trimmed);
    final Map<String, dynamic> payload =
        await _getJson('/api/search?q=$encoded');
    return _extractList(payload, 'items').map(ItemLocation.fromMap).toList();
  }

  @override
  Future<ItemLocation?> getItemLocation(int itemId) async {
    final http.Response response = await _client
        .get(_uri('/api/items/$itemId'), headers: _headers())
        .timeout(_requestTimeout);
    if (response.statusCode == 404) return null;
    return ItemLocation.fromMap(_decodeObjectResponse(response));
  }

  @override
  Future<void> updateItem(Item item) async {
    final int? itemId = item.id;
    if (itemId == null) {
      throw ArgumentError('Cannot update an item without id');
    }
    await _patchJson(
      '/api/items/$itemId',
      <String, dynamic>{
        'name': item.name,
        'category': item.category,
        'shortDescription': item.shortDescription,
        'photoPath': item.photoPath,
        'containerId': item.containerId,
        'quantity': item.quantity,
      },
    );
  }

  @override
  Future<void> deleteItem(int itemId) async {
    await _delete('/api/items/$itemId');
  }
}
