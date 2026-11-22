import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:home_scatolo/models/container.dart' as models;
import 'package:home_scatolo/models/house.dart';
import 'package:home_scatolo/models/item.dart';
import 'package:home_scatolo/models/item_location.dart';
import 'package:home_scatolo/models/room.dart';
import 'package:home_scatolo/services/remote_storage_service.dart';
import 'package:home_scatolo/services/storage_factory.dart';
import 'package:home_scatolo/services/storage_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('RemoteStorageService', () {
    test('lists and inserts houses with Bearer authentication', () async {
      final RemoteStorageService service = RemoteStorageService(
        baseUrl: 'https://scatolo.example.test/',
        apiToken: 'home-token',
        client: MockClient((http.Request request) async {
          expect(request.headers['Authorization'], 'Bearer home-token');
          if (request.method == 'POST' && request.url.path == '/api/houses') {
            final Map<String, dynamic> body =
                jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['name'], 'Casa Vaiano');
            return http.Response('{"id":7,"name":"Casa Vaiano"}', 201);
          }
          if (request.method == 'GET' && request.url.path == '/api/houses') {
            return http.Response(
              '{"houses":[{"id":7,"name":"Casa Vaiano"}]}',
              200,
            );
          }
          return http.Response('Not found', 404);
        }),
      );

      final int id = await service.insertHouse(const House(name: 'Casa Vaiano'));
      expect(id, 7);

      final List<House> houses = await service.getHouses();
      expect(houses, hasLength(1));
      expect(houses.single.name, 'Casa Vaiano');
    });

    test('fetches rooms, containers, quick-scan container, and items',
        () async {
      final RemoteStorageService service = RemoteStorageService(
        baseUrl: '',
        client: MockClient((http.Request request) async {
          if (request.method == 'GET' &&
              request.url.path == '/api/houses/1/rooms') {
            return http.Response(
              '{"rooms":[{"id":2,"name":"Cantina","houseId":1}]}',
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/rooms/2/containers') {
            return http.Response(
              '{"containers":[{"id":3,"name":"Scatola A","type":"scatolone","roomId":2}]}',
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/quick-scan-container') {
            return http.Response(
              '{"houseId":1,"roomId":2,"containerId":3}',
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/search' &&
              request.url.queryParameters['q'] == 'hdmi') {
            return http.Response(
              '{"items":[{"id":9,"name":"Cavo HDMI","category":"Elettronica","shortDescription":"2m","photoPath":null,"containerId":3,"insertedAt":"2026-11-22T18:00:00.000Z","quantity":2}]}',
              200,
            );
          }
          return http.Response('Not found', 404);
        }),
      );

      final List<Room> rooms = await service.getRooms(1);
      expect(rooms.single.name, 'Cantina');

      final List<models.Container> containers = await service.getContainers(2);
      expect(containers.single.type, models.ContainerType.scatolone);

      expect(await service.getOrCreateQuickScanContainer(), 3);

      final List<Item> matches = await service.searchItems('hdmi');
      expect(matches, hasLength(1));
      expect(matches.single.name, 'Cavo HDMI');
      expect(matches.single.quantity, 2);
    });

    test('reads and updates activeHouseId state', () async {
      String? storedValue;
      final RemoteStorageService service = RemoteStorageService(
        baseUrl: 'https://scatolo.example.test',
        client: MockClient((http.Request request) async {
          if (request.method == 'PUT' &&
              request.url.path == '/api/state/activeHouseId') {
            final Map<String, dynamic> body =
                jsonDecode(request.body) as Map<String, dynamic>;
            storedValue = body['value'] as String;
            return http.Response(
              '{"key":"activeHouseId","value":"$storedValue"}',
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/state/activeHouseId') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'key': 'activeHouseId',
                'value': storedValue,
              }),
              200,
            );
          }
          return http.Response('Not found', 404);
        }),
      );

      expect(await service.getActiveHouseId(), isNull);
      await service.setActiveHouseId(42);
      expect(await service.getActiveHouseId(), 42);
    });

    test('fetches item location, searches with location, updates and deletes item',
        () async {
      bool updated = false;
      bool deleted = false;
      final RemoteStorageService service = RemoteStorageService(
        baseUrl: 'https://scatolo.example.test',
        client: MockClient((http.Request request) async {
          if (request.method == 'GET' && request.url.path == '/api/items/9') {
            return http.Response(
              '{"id":9,"name":"Cavo HDMI","category":"Elettronica","shortDescription":"2m","photoPath":null,"containerId":3,"insertedAt":"2026-11-22T18:00:00.000Z","quantity":2,"houseName":"Casa Vaiano","roomName":"Cantina","containerName":"Scatola Cavi","containerType":"scatolone"}',
              200,
            );
          }
          if (request.method == 'GET' && request.url.path == '/api/containers') {
            return http.Response(
              '{"containers":[{"id":3,"name":"Scatola Cavi","type":"scatolone","roomId":2}]}',
              200,
            );
          }
          if (request.method == 'GET' && request.url.path == '/api/search') {
            return http.Response(
              '{"items":[{"id":9,"name":"Cavo HDMI","category":"Elettronica","shortDescription":"2m","photoPath":null,"containerId":3,"insertedAt":"2026-11-22T18:00:00.000Z","quantity":2,"houseName":"Casa Vaiano","roomName":"Cantina","containerName":"Scatola Cavi","containerType":"scatolone"}]}',
              200,
            );
          }
          if (request.method == 'PATCH' && request.url.path == '/api/items/9') {
            updated = true;
            return http.Response('{"id":9}', 200);
          }
          if (request.method == 'DELETE' && request.url.path == '/api/items/9') {
            deleted = true;
            return http.Response('', 204);
          }
          return http.Response('Not found', 404);
        }),
      );

      final ItemLocation? detail = await service.getItemLocation(9);
      expect(detail, isNotNull);
      expect(detail!.pathLabel, 'Casa Vaiano › Cantina › Scatola Cavi');

      final List<ItemLocation> results =
          await service.searchItemsWithLocation('hdmi');
      expect(results.single.pathLabel, 'Casa Vaiano › Cantina › Scatola Cavi');

      final List<models.Container> allContainers =
          await service.getAllContainers();
      expect(allContainers, hasLength(1));

      await service.updateItem(detail.item.copyWith(quantity: 3));
      expect(updated, isTrue);

      await service.deleteItem(9);
      expect(deleted, isTrue);
    });
  });

  group('createStorageService', () {
    test('selects local or remote storage according to mode', () {
      expect(createStorageService(mode: 'local'), isA<StorageService>());
      expect(
        createStorageService(mode: 'local'),
        isNot(isA<RemoteStorageService>()),
      );
      expect(createStorageService(mode: 'remote'), isA<RemoteStorageService>());
    });
  });
}
