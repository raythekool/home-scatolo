class House {
  const House({
    this.id,
    required this.name,
  });

  final int? id;
  final String name;

  factory House.fromMap(Map<String, dynamic> map) {
    return House(
      id: map['id'] as int?,
      name: map['name'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      'name': name,
    };
  }

  House copyWith({int? id, String? name}) {
    return House(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }
}
