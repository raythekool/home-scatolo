class Item {
  const Item({
    this.id,
    required this.name,
    required this.category,
    required this.shortDescription,
    this.photoPath,
    required this.containerId,
    required this.insertedAt,
  });

  final int? id;
  final String name;
  final String category;
  final String shortDescription;
  final String? photoPath;
  final int containerId;
  final DateTime insertedAt;

  factory Item.fromMap(Map<String, dynamic> map) {
    return Item(
      id: map['id'] as int?,
      name: map['name'] as String,
      category: map['category'] as String,
      shortDescription: map['shortDescription'] as String,
      photoPath: map['photoPath'] as String?,
      containerId: map['containerId'] as int,
      insertedAt: DateTime.parse(map['insertedAt'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (id != null) 'id': id,
      'name': name,
      'category': category,
      'shortDescription': shortDescription,
      'photoPath': photoPath,
      'containerId': containerId,
      'insertedAt': insertedAt.toIso8601String(),
    };
  }
}
