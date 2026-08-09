enum ContainerType {
  armadio,
  scatolone,
  libreria,
  cassetto;

  String toValue() => name;

  static ContainerType fromValue(String value) {
    return ContainerType.values.firstWhere(
      (ContainerType t) => t.name == value,
      orElse: () => throw ArgumentError('Unknown ContainerType: $value'),
    );
  }
}

class Container {
  const Container({
    this.id,
    required this.name,
    required this.type,
    required this.roomId,
  });

  final int? id;
  final String name;
  final ContainerType type;
  final int roomId;

  factory Container.fromMap(Map<String, dynamic> map) {
    return Container(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: ContainerType.fromValue(map['type'] as String),
      roomId: map['roomId'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      'name': name,
      'type': type.toValue(),
      'roomId': roomId,
    };
  }

  Container copyWith({
    int? id,
    String? name,
    ContainerType? type,
    int? roomId,
  }) {
    return Container(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      roomId: roomId ?? this.roomId,
    );
  }
}
