import 'package:flutter_test/flutter_test.dart';
import 'package:truearena/core/fuzzy_match.dart';

void main() {
  group('similarity', () {
    test('identical strings score 1.0', () {
      expect(similarity('giraffe', 'giraffe'), 1.0);
    });

    test('completely different strings score low', () {
      expect(similarity('cat', 'dog'), lessThan(0.34));
    });

    test('a close misspelling scores fairly high but not perfect', () {
      final s = similarity('gerraffe', 'giraffe');
      expect(s, greaterThan(0.7));
      expect(s, lessThan(1.0));
    });
  });

  group('isCloseMatch', () {
    test('exact single-word match', () {
      expect(isCloseMatch('is that a giraffe', 'giraffe', 0.8), isTrue);
    });

    test('close misspelling matches at a loose threshold', () {
      expect(isCloseMatch('it looks like a gerraffe to me', 'giraffe', 0.75), isTrue);
    });

    test('close misspelling rejected at a strict threshold', () {
      expect(isCloseMatch('it looks like a gerraffe to me', 'giraffe', 0.99), isFalse);
    });

    test('unrelated word never matches regardless of threshold', () {
      expect(isCloseMatch('is that an elephant', 'giraffe', 0.5), isFalse);
    });

    test('is case- and punctuation-insensitive', () {
      expect(isCloseMatch('GIRAFFE!!', 'giraffe', 0.99), isTrue);
    });

    test('multi-word target matches when said in full', () {
      expect(isCloseMatch('i think it is a polar bear', 'polar bear', 0.85), isTrue);
    });

    test('multi-word target also matches on its distinctive single word', () {
      // "bear" alone is a reasonable single-word guess signal for "polar bear".
      expect(isCloseMatch('some kind of bear', 'polar bear', 0.7), isTrue);
    });

    test('empty heard text never matches', () {
      expect(isCloseMatch('', 'giraffe', 0.5), isFalse);
    });

    test('empty target never matches', () {
      expect(isCloseMatch('giraffe', '', 0.5), isFalse);
    });
  });
}
