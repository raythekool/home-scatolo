class Container {
  const Container({
    this.id,
    required this.name,
    required this.type,
    required this.roomId,
  });

  final int? id;
  final String name;
  final String type;
  final int roomId;

  factory Container.fromMap(Map<String, dynamic> map) {
    return Container(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: map['type'] as String,
      roomId: map['roomId'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      'name': name,
      'type': type,
      'roomId': roomId,
    };
  }
}
