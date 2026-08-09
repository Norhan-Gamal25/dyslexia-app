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

  /// Key for ANY two different letters ("e-o", "a-s", ...). Unlike
  /// [_pairKeyFor] this also covers vowel and other mixups that are not in
  /// the classic dyslexia list (e.g. a child hearing "red" and saying "rod"),
  /// so the analysis can tell the child "you mix up e and o" explicitly.
  static String? _anyPairKey(String a, String b) {
    if (a.isEmpty || b.isEmpty || a == b) return null;
    final sorted = [a, b]..sort();
    return '${sorted[0]}-${sorted[1]}';
  }

  static String _stripPunctuation(String word) =>
      word.replaceAll(RegExp(r'[^\w]'), '');

  /// True when [a] and [b] are a commonly swapped letter pair (b/d, p/q, ...).
  static bool isConfusable(String a, String b) => _pairKeyFor(a, b) != null;

  /// The letters of [expected] that are completely missing from [actual],
  /// e.g. expected "ship" / actual "hip" -> ['s']. Ordered by first missing.
  static List<String> missingLetters(String expected, String actual) {
    final e = _stripPunctuation(expected).toLowerCase();
    final a = _stripPunctuation(actual).toLowerCase();
    final seen = a.split('').toSet();
    final missing = <String>[];
    for (final letter in e.split('')) {
      if (!seen.contains(letter) && !missing.contains(letter)) {
        missing.add(letter);
      }
    }
    return missing;
  }

  /// Compares two strings word-by-word using sequence alignment (the same
  /// grading idea the screens already used) and additionally looks for
  /// letter-level confusions inside words that are "almost right" (same
  /// length, one or two letters off) rather than totally different words.
  ///
  /// Unlike strict positional comparison, misalignments caused by a single
  /// inserted or skipped word (very common with handwriting OCR) no longer
  /// shift every later word onto the wrong partner.
  static WordComparisonResult compare(String expected, String actual) {
    final expectedWords = expected
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map(_stripPunctuation)
        .where((w) => w.isNotEmpty)
        .toList();
    final actualWords = actual
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map(_stripPunctuation)
        .where((w) => w.isNotEmpty)
        .toList();

    if (expectedWords.isEmpty) {
      return WordComparisonResult(
        correctWords: 0,
        totalWords: 0,
        accuracy: 0,
        confusions: const {},
      );
    }

    // Semantics of a word pair for alignment scoring.
    // Returns: (score, correct, confusionKey?)
    String scoreWord(String expected, String actual) {
      if (expected == actual) return 'exact';
      if (expected.length == actual.length) {
        // Any letter that differs is recorded as a mixup ("e-o", "b-d", ...),
        // not just the classic dyslexia pairs. Multiple keys are joined with
        // a pipe so a word can flag several letters at once.
        final keys = <String>[];
        for (var c = 0; c < expected.length; c++) {
          if (expected[c] != actual[c]) {
            final key = _anyPairKey(expected[c], actual[c]);
            if (key != null) keys.add(key);
          }
        }
        // Only count it as a "letter mixup" (not just a wrong word) when the
        // word is otherwise close to correct.
        if (keys.isNotEmpty && keys.length <= 2) return 'near:${keys.join('|')}';
      }
      return 'wrong';
    }

    // Needleman-Wunsch global alignment over word tokens. Score a true
    // match higher than a near-miss, penalize gaps so we track which actual
    // words map to which expected words.
    final n = expectedWords.length;
    final m = actualWords.length;
    const matchScore = 3;
    const nearScore = 1;
    const gapScore = -2;
    const mismatchScore = -3;

    final scores = List.generate(n + 1, (_) => List.filled(m + 1, 0));
    final pointers = List.generate(
      n + 1,
      (_) => List<String>.filled(m + 1, ''),
    );

    for (var i = 0; i <= n; i++) {
      scores[i][0] = i * gapScore;
      pointers[i][0] = 'up';
    }
    for (var j = 0; j <= m; j++) {
      scores[0][j] = j * gapScore;
      pointers[0][j] = 'left';
    }

    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final state = scoreWord(expectedWords[i - 1], actualWords[j - 1]);
        final diagScore =
            scores[i - 1][j - 1] +
            (state == 'exact'
                ? matchScore
                : state.startsWith('near:')
                ? nearScore
                : mismatchScore);
        final upScore = scores[i - 1][j] + gapScore;
        final leftScore = scores[i][j - 1] + gapScore;
        if (diagScore >= upScore && diagScore >= leftScore) {
          scores[i][j] = diagScore;
          pointers[i][j] = 'diag:$state';
        } else if (upScore >= leftScore) {
          scores[i][j] = upScore;
          pointers[i][j] = 'up';
        } else {
          scores[i][j] = leftScore;
          pointers[i][j] = 'left';
        }
      }
    }

    // Backtrack.
    var i = n, j = m;
    int correct = 0;
    final confusions = <String, int>{};
    while (i > 0 || j > 0) {
      if (i > 0 && pointers[i][j] == 'up') {
        i--;
      } else if (j > 0 && pointers[i][j] == 'left') {
        j--;
      } else {
        final state = pointers[i][j];
        if (state.startsWith('diag:exact')) {
          correct++;
        } else if (state.startsWith('diag:near:')) {
          // Count the near-miss as correct for the child, but still flag
          // the recurring letters so it feeds the parent dashboard.
          correct++;
          final keys = state.substring('diag:near:'.length).split('|');
          for (final key in keys) {
            confusions[key] = (confusions[key] ?? 0) + 1;
          }
        }
        i--;
        j--;
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
