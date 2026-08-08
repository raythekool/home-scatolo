class Room {
  const Room({
    this.id,
    required this.name,
    required this.houseId,
  });

  final int? id;
  final String name;
  final int houseId;

  factory Room.fromMap(Map<String, dynamic> map) {
    return Room(
      id: map['id'] as int?,
      name: map['name'] as String,
      houseId: map['houseId'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      'name': name,
      'houseId': houseId,
    };
  }
}
