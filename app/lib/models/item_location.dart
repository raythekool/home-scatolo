import 'container.dart' as models;
import 'item.dart';

class ItemLocation {
  const ItemLocation({
    required this.item,
    required this.houseName,
    required this.roomName,
    required this.containerName,
    required this.containerType,
  });

  final Item item;
  final String houseName;
  final String roomName;
  final String containerName;
  final models.ContainerType containerType;

  String get pathLabel => '$houseName › $roomName › $containerName';

  factory ItemLocation.fromMap(Map<String, dynamic> map) {
    final String rawType = map['containerType'] as String? ?? 'scatolone';
    return ItemLocation(
      item: Item.fromMap(map),
      houseName: map['houseName'] as String? ?? '',
      roomName: map['roomName'] as String? ?? '',
      containerName: map['containerName'] as String? ?? '',
      containerType: models.ContainerType.fromValue(rawType),
    );
  }
}
