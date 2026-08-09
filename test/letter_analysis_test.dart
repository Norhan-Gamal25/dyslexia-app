import 'package:flutter_test/flutter_test.dart';
import 'package:verbix/services/letter_analysis.dart';

void main() {
  group('LetterAnalysis.compare', () {
    test('exact match scores 100%', () {
      final result = LetterAnalysis.compare(
        'the cat sat on a mat',
        'the cat sat on a mat',
      );
      expect(result.correctWords, 6);
      expect(result.totalWords, 6);
      expect(result.accuracy, 100);
      expect(result.confusions, isEmpty);
    });

    test('ignores punctuation and casing', () {
      final result = LetterAnalysis.compare(
        'The cat, sat on a mat!',
        'the cat sat on a mat',
      );
      expect(result.correctWords, 6);
      expect(result.accuracy, 100);
    });

    test('alignment allows one word to be inserted without cascading', () {
      // A single "and" added by the child/OCR should not shift everything
      // after it onto the wrong partner.
      final result = LetterAnalysis.compare(
        'the cat sat on a mat',
        'the cat sat down on a mat',
      );
      expect(result.correctWords, 6);
      expect(result.totalWords, 6);
      expect(result.accuracy, 100);
    });

    test('near-miss b/d counts as correct but flags a confusion', () {
      final result = LetterAnalysis.compare(
        'big dog',
        'dig bog', // exact swap of b and d
      );
      expect(result.correctWords, 2);
      expect(result.accuracy, 100);
      expect(result.confusions['b-d'], 2);
    });

    test('flags any letter mixup like e/o and a/e, not just classic pairs',
        () {
      // "red" said as "rod": the e/o vowel mixup must be reported even
      // though e/o is not in the classic dyslexia pair list.
      final result = LetterAnalysis.compare('red', 'rod');
      expect(result.correctWords, 1);
      expect(result.accuracy, 100);
      expect(result.confusions.keys, contains('e-o'));

      // A word with two mixups flags both letters.
      final two = LetterAnalysis.compare('head', 'higd');
      expect(two.confusions.keys, contains('e-i'));
      expect(two.confusions.keys, contains('a-g'));
    });

    test('missing words are penalized', () {
      final result = LetterAnalysis.compare(
        'the cat sat on a mat',
        'the cat mat', // missing half the words
      );
      expect(result.correctWords, greaterThan(0));
      expect(result.correctWords, lessThan(6));
      expect(result.accuracy, lessThan(100));
    });

    test('empty expected returns zero without crashing', () {
      final result = LetterAnalysis.compare('   ', '');
      expect(result.totalWords, 0);
      expect(result.accuracy, 0);
    });
  });

  group('LetterAnalysis.missingLetters', () {
    test('reports letters completely absent from the actual text', () {
      expect(LetterAnalysis.missingLetters('ship', 'hip'), ['s']);
      expect(LetterAnalysis.missingLetters('cat', ''), ['c', 'a', 't']);
    });

    test('returns the letters missing from a near-miss word', () {
      expect(LetterAnalysis.missingLetters('red', 'rod'), ['e']);
    });

    test('returns nothing when letters all appear', () {
      expect(LetterAnalysis.missingLetters('cat', 'cat'), isEmpty);
    });
  });
}