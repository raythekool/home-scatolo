enum RecognitionAction { add, mergeQuantity, review, ignore }

class RecognitionCandidate {
  const RecognitionCandidate({
    required this.name,
    required this.category,
    required this.shortDescription,
    required this.quantity,
    required this.confidence,
  })  : assert(quantity > 0),
        assert(confidence >= 0 && confidence <= 1);

  final String name;
  final String category;
  final String shortDescription;
  final int quantity;
  final double confidence;

  factory RecognitionCandidate.fromJson(Map<String, dynamic> json) {
    final dynamic confidence = json['confidence'];
    return RecognitionCandidate(
      name: json['name'] as String,
      category: json['category'] as String,
      shortDescription: json['shortDescription'] as String,
      quantity: json['quantity'] as int,
      confidence:
          confidence is int ? confidence.toDouble() : confidence as double,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'category': category,
      'shortDescription': shortDescription,
      'quantity': quantity,
      'confidence': confidence,
    };
  }
}

class RecognitionDecision {
  const RecognitionDecision({
    required this.candidate,
    required this.action,
    this.matchedItem,
  });

  final RecognitionCandidate candidate;
  final RecognitionAction action;
  final int? matchedItem;
}
