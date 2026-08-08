import 'package:flutter_test/flutter_test.dart';
import 'package:home_scatolo/models/container.dart' as c;
import 'package:home_scatolo/models/house.dart';
import 'package:home_scatolo/models/item.dart';
import 'package:home_scatolo/models/room.dart';

void main() {
  group('House', () {
    test('fromMap / toMap roundtrip (with id)', () {
      final map = <String, dynamic>{'id': 1, 'name': 'Casa Test'};
      final house = House.fromMap(map);
      expect(house.id, 1);
      expect(house.name, 'Casa Test');
      expect(house.toMap(), map);
    });

    test('toMap omits id when null', () {
      final house = House(name: 'Senza ID');
      expect(house.toMap().containsKey('id'), isFalse);
    });

    test('copyWith', () {
      const house = House(id: 1, name: 'Vecchio');
      final updated = house.copyWith(name: 'Nuovo');
      expect(updated.id, 1);
      expect(updated.name, 'Nuovo');
    });
  });

  group('Room', () {
    test('fromMap / toMap roundtrip', () {
      final map = <String, dynamic>{'id': 2, 'name': 'Salotto', 'houseId': 1};
      final room = Room.fromMap(map);
      expect(room.id, 2);
      expect(room.name, 'Salotto');
      expect(room.houseId, 1);
      expect(room.toMap(), map);
    });

    test('toMap omits id when null', () {
      final room = Room(name: 'Cucina', houseId: 1);
      expect(room.toMap().containsKey('id'), isFalse);
    });

    test('copyWith', () {
      const room = Room(id: 2, name: 'Salotto', houseId: 1);
      final updated = room.copyWith(name: 'Soggiorno');
      expect(updated.id, 2);
      expect(updated.name, 'Soggiorno');
      expect(updated.houseId, 1);
    });
  });

  group('Container', () {
    test('fromMap / toMap roundtrip', () {
      final map = <String, dynamic>{
        'id': 3,
        'name': 'Armadio',
        'type': 'armadio',
        'roomId': 2,
      };
      final container = c.Container.fromMap(map);
      expect(container.id, 3);
      expect(container.name, 'Armadio');
      expect(container.type, c.ContainerType.armadio);
      expect(container.roomId, 2);
      expect(container.toMap(), map);
    });

    test('toMap omits id when null', () {
      final container = c.Container(
        name: 'Box',
        type: c.ContainerType.scatolone,
        roomId: 1,
      );
      expect(container.toMap().containsKey('id'), isFalse);
    });

    test('ContainerType.fromValue unknown throws', () {
      expect(
        () => c.ContainerType.fromValue('unknown'),
        throwsArgumentError,
      );
    });

    test('copyWith', () {
      final container = c.Container(
        id: 3,
        name: 'Armadio',
        type: c.ContainerType.armadio,
        roomId: 2,
      );
      final updated = container.copyWith(type: c.ContainerType.libreria);
      expect(updated.type, c.ContainerType.libreria);
      expect(updated.name, 'Armadio');
    });
  });

  group('Item', () {
    test('fromMap / toMap roundtrip', () {
      final now = DateTime(2024, 1, 1);
      final map = <String, dynamic>{
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

    test('toMap omits id when null', () {
      final item = Item(
        name: 'Oggetto',
        category: 'varie',
        shortDescription: 'desc',
        containerId: 1,
        insertedAt: DateTime(2024),
      );
      expect(item.toMap().containsKey('id'), isFalse);
    });

    test('copyWith', () {
      final item = Item(
        id: 4,
        name: 'Libro',
        category: 'libri',
        shortDescription: 'desc',
        containerId: 3,
        insertedAt: DateTime(2024),
      );
      final updated = item.copyWith(category: 'elettronica');
      expect(updated.category, 'elettronica');
      expect(updated.name, 'Libro');
    });
  });
}
