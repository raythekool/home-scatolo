import 'package:flutter_test/flutter_test.dart';
import 'package:home_scatolo/models/container.dart' as c;
import 'package:home_scatolo/models/house.dart';
import 'package:home_scatolo/models/item.dart';
import 'package:home_scatolo/models/room.dart';

void main() {
  group('House', () {
    test('fromMap / toMap roundtrip', () {
      final map = {'id': 1, 'name': 'Casa Test'};
      final house = House.fromMap(map);
      expect(house.id, 1);
      expect(house.name, 'Casa Test');
      expect(house.toMap(), map);
    });
  });
  group('Room', () {
    test('fromMap / toMap roundtrip', () {
      final map = {'id': 2, 'name': 'Salotto', 'houseId': 1};
      final room = Room.fromMap(map);
      expect(room.id, 2);
      expect(room.name, 'Salotto');
      expect(room.houseId, 1);
      expect(room.toMap(), map);
    });
  });
  group('Container', () {
    test('fromMap / toMap roundtrip', () {
      final map = {'id': 3, 'name': 'Armadio', 'type': 'armadio', 'roomId': 2};
      final container = c.Container.fromMap(map);
      expect(container.id, 3);
      expect(container.name, 'Armadio');
      expect(container.type, 'armadio');
      expect(container.roomId, 2);
      expect(container.toMap(), map);
    });
  });
  group('Item', () {
    test('fromMap / toMap roundtrip', () {
      final now = DateTime(2024, 1, 1);
      final map = {
        'id': 4,
        'name': 'Libro',
        'category': 'libri',
        'shortDescription': 'Un bel libro',
        'photoPath': null,
        'containerId': 3,
        'insertedAt': now.toIso8601String(),
      };
      final item = Item.fromMap(map);
      expect(item.id, 4);
      expect(item.name, 'Libro');
      expect(item.toMap(), map);
    });
  });
}
