import '../models/item.dart';
import '../models/recognition_candidate.dart';

class DuplicateMatcher {
  const DuplicateMatcher();

  RecognitionDecision decide({
    required RecognitionCandidate candidate,
    required Iterable<Item> containerItems,
  }) {
    final String candidateName = _normalize(candidate.name);
    final String candidateCategory = _normalize(candidate.category);
    final List<Item> nameMatches = containerItems
        .where((Item item) => _normalize(item.name) == candidateName)
        .toList();

    if (nameMatches.length == 1) {
      final Item match = nameMatches.single;
      if (_normalize(match.category) == candidateCategory) {
        return RecognitionDecision(
          candidate: candidate,
          action: RecognitionAction.mergeQuantity,
          matchedItem: match.id,
        );
      }
      return RecognitionDecision(
        candidate: candidate,
        action: RecognitionAction.review,
        matchedItem: match.id,
      );
    }

    if (nameMatches.length > 1) {
      return RecognitionDecision(
        candidate: candidate,
        action: RecognitionAction.review,
      );
    }

    return RecognitionDecision(
      candidate: candidate,
      action: RecognitionAction.add,
    );
  }

  String _normalize(String value) {
    const Map<String, String> accents = <String, String>{
      'à': 'a',
      'á': 'a',
      'è': 'e',
      'é': 'e',
      'ì': 'i',
      'í': 'i',
      'ò': 'o',
      'ó': 'o',
      'ù': 'u',
      'ú': 'u',
    };
    final String lowerCase = value.trim().toLowerCase();
    final String withoutAccents = lowerCase
        .split('')
        .map((String character) => accents[character] ?? character)
        .join();
    return withoutAccents.replaceAll(RegExp(r'\s+'), ' ');
  }
}