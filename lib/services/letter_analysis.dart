/// Utilities for comparing an expected passage/word against what the child
/// actually wrote or said, and flagging letter-level mixups that are common
/// in dyslexia (b/d, p/q, m/w, ...).
///
/// This builds on the word-matching the app already did in
/// WritingPatternScreen / SpeechPatternScreen, and additionally looks
/// inside near-miss words for a single confused letter.
class WordComparisonResult {
  final int correctWords;
  final int totalWords;
  final double accuracy;
  final Map<String, int> confusions; // key: "a-b" (sorted pair), value: count

  WordComparisonResult({
    required this.correctWords,
    required this.totalWords,
    required this.accuracy,
    required this.confusions,
  });
}

class LetterAnalysis {
  // Pairs of letters that are frequently swapped by dyslexic readers/writers.
  static const List<List<String>> _confusablePairs = [
    ['b', 'd'],
    ['p', 'q'],
    ['m', 'w'],
    ['n', 'u'],
    ['f', 't'],
    ['s', 'z'],
    ['i', 'l'],
    ['g', 'q'],
    ['v', 'w'],
  ];

  static String? _pairKeyFor(String a, String b) {
    for (final pair in _confusablePairs) {
      if ((pair[0] == a && pair[1] == b) || (pair[0] == b && pair[1] == a)) {
        final sorted = [a, b]..sort();
        return '${sorted[0]}-${sorted[1]}';
      }
    }
    return null;
  }

  static String _stripPunctuation(String word) =>
      word.replaceAll(RegExp(r'[^\w]'), '');

  /// Compares two strings word-by-word (same grading approach the screens
  /// already used) and additionally looks for letter-level confusions
  /// inside words that are "almost right" (same length, one or two letters
  /// off) rather than totally different words.
  static WordComparisonResult compare(String expected, String actual) {
    final expectedWords = expected
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final actualWords = actual
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    int correct = 0;
    final confusions = <String, int>{};

    for (var i = 0; i < expectedWords.length; i++) {
      if (i >= actualWords.length) break;
      final expectedWord = _stripPunctuation(expectedWords[i]);
      final actualWord = _stripPunctuation(actualWords[i]);
      if (expectedWord.isEmpty) continue;
      if (expectedWord == actualWord) {
        correct++;
        continue;
      }
      if (expectedWord.length == actualWord.length) {
        var mismatches = 0;
        String? lastKey;
        for (var c = 0; c < expectedWord.length; c++) {
          if (expectedWord[c] != actualWord[c]) {
            mismatches++;
            final key = _pairKeyFor(expectedWord[c], actualWord[c]);
            if (key != null) lastKey = key;
          }
        }
        // Only count it as a "letter confusion" (not just a wrong word)
        // when the word is otherwise close to correct.
        if (mismatches <= 2 && lastKey != null) {
          confusions[lastKey] = (confusions[lastKey] ?? 0) + 1;
        }
      }
    }

    final total = expectedWords.length;
    final accuracy = total == 0 ? 0.0 : (correct / total) * 100;
    return WordComparisonResult(
      correctWords: correct,
      totalWords: total,
      accuracy: accuracy,
      confusions: confusions,
    );
  }

  static String labelFor(String pairKey) => pairKey.replaceAll('-', ' / ');

  /// A short, concrete suggested exercise for a given confusion pair key
  /// such as "b-d". Falls back to a generic tip for pairs not in the list.
  static String exerciseFor(String pairKey) {
    switch (pairKey) {
      case 'b-d':
        return 'Try the "bed" trick: draw a bed shape using a lowercase b '
            'and d as the two posts, then trace each letter while saying '
            'its sound out loud.';
      case 'p-q':
        return 'Practice writing p and q on lined paper, exaggerating which '
            'way the tail points, while saying "p points left, q points '
            'right".';
      case 'm-w':
        return 'Have the child count the "humps" out loud while tracing m '
            '(two humps down) and w (two points up) to feel the difference.';
      case 'n-u':
        return 'Practice tracing n and u with a starting-dot cue, saying '
            '"n has a bridge, u has a bucket" while writing each one.';
      case 'f-t':
        return 'Practice tracing f and t slowly, marking the crossbar '
            'height with a colored line so the difference stands out.';
      case 's-z':
        return 'Practice tracing s and z side by side, saying the sound '
            'each letter makes to reinforce the visual difference.';
      case 'i-l':
        return 'Practice writing i and l next to familiar words, pointing '
            'out the dot on the i as the key difference.';
      case 'g-q':
        return 'Practice tracing g and q, highlighting which way the '
            'letter\'s tail curves.';
      case 'v-w':
        return 'Practice tracing v and w, counting the points (one vs two) '
            'out loud while writing.';
      default:
        return 'Practice tracing both letters side by side and saying '
            'their sounds out loud to reinforce the difference.';
    }
  }
}
