import 'package:flutter_test/flutter_test.dart';
import 'package:home_scatolo/models/item.dart';
import 'package:home_scatolo/models/recognition_candidate.dart';
import 'package:home_scatolo/services/duplicate_matcher.dart';

void main() {
  const DuplicateMatcher matcher = DuplicateMatcher();

  RecognitionCandidate candidate({
    String name = 'Libro di cucina',
    String category = 'Libri',
  }) {
    return RecognitionCandidate(
      name: name,
      category: category,
      shortDescription: 'Ricettario',
      quantity: 1,
      confidence: .9,
    );
  }

  Item item({
    int? id = 1,
    String name = 'Libro di cucina',
    String category = 'Libri',
    int containerId = 5,
  }) {
    return Item(
      id: id,
      name: name,
      category: category,
      shortDescription: 'Ricettario',
      containerId: containerId,
      insertedAt: DateTime(2024, 1, 1),
    );
  }

  group('DuplicateMatcher', () {
    test('merges exact name and category matches', () {
      final RecognitionDecision decision = matcher.decide(
        candidate: candidate(),
        containerItems: <Item>[item()],
      );

      expect(decision.action, RecognitionAction.mergeQuantity);
      expect(decision.matchedItem, 1);
    });

    test('normalizes case, whitespace, and accents before matching', () {
      final RecognitionDecision decision = matcher.decide(
        candidate: candidate(name: '  LIBRO   DI  CUCINA ', category: 'Lìbri'),
        containerItems: <Item>[item()],
      );

      expect(decision.action, RecognitionAction.mergeQuantity);
      expect(decision.matchedItem, 1);
    });

    test('requires review when an equal name has another category', () {
      final RecognitionDecision decision = matcher.decide(
        candidate: candidate(category: 'Elettronica'),
        containerItems: <Item>[item()],
      );

      expect(decision.action, RecognitionAction.review);
      expect(decision.matchedItem, 1);
    });

    test('adds an unseen item', () {
      final RecognitionDecision decision = matcher.decide(
        candidate: candidate(name: 'Lampada'),
        containerItems: <Item>[item()],
      );

      expect(decision.action, RecognitionAction.add);
      expect(decision.matchedItem, isNull);
    });

    test('requires review when multiple matching items exist', () {
      final RecognitionDecision decision = matcher.decide(
        candidate: candidate(),
        containerItems: <Item>[item(id: 1), item(id: 2)],
      );

      expect(decision.action, RecognitionAction.review);
      expect(decision.matchedItem, isNull);
    });
  });
}