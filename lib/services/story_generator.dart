import 'dart:math';

/// One generated AI story, ready for the StoryScreen.
class Story {
  final String title;
  final int level; // 1 = beginner, 2 = developing, 3 = confident
  final List<String> sentences;
  final Set<String> focusLetters;
  final List<String> usedWords;

  Story({
    required this.title,
    required this.level,
    required this.sentences,
    required this.focusLetters,
    required this.usedWords,
  });
}

/// On-device story generator.
///
/// Turns the child's practice words and their recurring trouble letters into
/// a short, readable story with a proper beginning, middle and end. It follows
/// one main character from start to finish (so the story stays coherent),
/// weaves in the child's practice words naturally, and gives each trouble
/// letter a "letter spotlight" sentence that pairs the letter with a real word
/// starting with it (e.g. "Ball starts with the letter b").
///
/// Sentence length and complexity adapt to the child's reading level (derived
/// from past session accuracy), and the output varies on each call - all
/// without a network request, API key, or privacy risk.
class StoryGenerator {
  StoryGenerator();

  static const int defaultLevel = 2;

  /// Fallback practice words used when Firestore has none (e.g. offline).
  static const List<String> exampleWords = [
    'cat',
    'dog',
    'bird',
    'tree',
    'ball',
    'book',
    'ship',
    'bike',
    'star',
    'door',
    'light',
    'phone',
    'water',
    'window',
    'garden',
  ];

  /// Maps average session accuracy to a reading level 1-3.
  static int levelFromAccuracy(double? averageAccuracy) {
    if (averageAccuracy == null) return 2;
    if (averageAccuracy < 60) return 1;
    if (averageAccuracy < 85) return 2;
    return 3;
  }

  /// Extracts the individual confused letters (e.g. [b, d] for "b-d") that
  /// the child mixed up most in past sessions.
  static Set<String> lettersFromConfusions(Map<String, int> confusions) {
    final letters = <String>{};
    final sorted = confusions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted.take(3)) {
      for (final part in entry.key.split('-')) {
        if (part.isNotEmpty) letters.add(part);
      }
      if (letters.length >= 4) break;
    }
    if (letters.isEmpty) {
      letters.add('b');
      letters.add('d');
    }
    return letters;
  }

  static const Map<String, String> _wordForLetter = {
    'a': 'apple',
    'b': 'ball',
    'c': 'cat',
    'd': 'dog',
    'e': 'egg',
    'f': 'fish',
    'g': 'goat',
    'h': 'hat',
    'i': 'ink',
    'j': 'jam',
    'k': 'kite',
    'l': 'leaf',
    'm': 'moon',
    'n': 'nut',
    'o': 'ocean',
    'p': 'pig',
    'q': 'queen',
    'r': 'rabbit',
    's': 'sun',
    't': 'tree',
    'u': 'umbrella',
    'v': 'van',
    'w': 'wind',
    'x': 'fox',
    'y': 'yarn',
    'z': 'zoo',
  };

  /// Builds a story around [words] and [troubleLetters] adjusted to [level].
  /// Deterministic for a given [seed], so tapping "New story" produces a
  /// different one each time.
  Story generate({
    required List<String> words,
    required Set<String> troubleLetters,
    required int level,
    int seed = 0,
  }) {
    final rng = Random(seed);

    // Practice words that aren't obviously junk (single words preferred so
    // the story reads naturally, but fall back to anything provided).
    final practice = words
        .where((w) => w.trim().isNotEmpty)
        .map((w) => w.trim().toLowerCase())
        .toList();

    // The hero must always be an animate character: a story where the hero is
    // an object drawn from the practice words ("a little garden went out to
    // explore the town") reads as nonsense. Practice words are woven in later
    // as things the character finds instead.
    const heroes = [
      'cat', 'dog', 'fox', 'bear', 'mouse', 'rabbit', 'goat', 'owl',
      'pig', 'frog', 'pony', 'duck', 'dragon', 'panda', 'whale', 'lion',
    ];
    final hero = heroes[rng.nextInt(heroes.length)];
    var friend = heroes[rng.nextInt(heroes.length)];
    while (friend == hero) {
      friend = heroes[rng.nextInt(heroes.length)];
    }
    // Avoid a misplaced article: "a cat", "a bird", but "an egg"/"an umbrella".
    final article = _articleFor(hero);

    // Object words the hero can discover on the adventure. Short single words
    // read best; fall back to a small built-in set when there are none.
    final objectPool = practice
        .where((w) => !heroes.contains(w) && w.length <= 10)
        .toList();
    final fallbackObjects = const ['ball', 'book', 'shell', 'feather', 'stone'];
    final candidates = objectPool.isNotEmpty ? objectPool : fallbackObjects;
    final woven = <String>{};
    while (woven.length < 2 && woven.length < candidates.length) {
      woven.add(candidates[rng.nextInt(candidates.length)]);
    }
    final objectsList = woven.toList();

    // A helper that returns a correctly articulated noun ("an egg").
    String withArticle(String noun) => '${_articleFor(noun)} $noun';

    final letterList =
        (troubleLetters.isEmpty ? const {'b', 'd'} : troubleLetters).toList()
          ..sort();

    final usedWords = <String>{hero, friend, ...woven};
    final sentences = <String>[];

    String cap(String s) {
      if (s.isEmpty) return s;
      return s[0].toUpperCase() + s.substring(1);
    }

    void push(String s) {
      final clean = cap(s.trim());
      if (clean.isNotEmpty && !sentences.contains(clean)) {
        sentences.add(clean);
      }
    }

    // --- Opening: introduce the hero --------------------------------------
    if (level == 1) {
      push('This is a story about $article $hero.');
      push('The $hero was small but brave.');
    } else if (level == 2) {
      push('One fine day, a little $hero went out to explore the town.');
      push('The $hero had a purple hat and a happy smile.');
    } else {
      push(
        'Long ago, in a cozy corner of the world, a clever $hero woke up '
        'to a shining morning.',
      );
      push('The $hero decided that today would be a day to remember.');
    }

    // --- Letter spotlight: each focus letter with a matching word ---------
    // Every focus letter must appear, so list them together, then pair one
    // or two of them with a real word that starts with that letter.
    if (level == 1) {
      push('Today the letters we practice are ${letterList.join(' and ')}.');
    } else if (level == 2) {
      push(
        '"The letters we practice today are ${letterList.join(' and ')}," '
        'said the $hero.',
      );
    } else {
      push(
        '"Every letter wakes up its own sound," the $hero explained. '
        '"Today we listen for ${letterList.join(' and ')}."',
      );
    }

    final pairs = <List<String>>[];
    for (var i = 0; i < letterList.length; i += 2) {
      pairs.add(letterList.sublist(i, min(i + 2, letterList.length)));
    }
    for (final pair in pairs) {
      final words100 = pair.map((l) => _wordForLetter[l] ?? 'ball').toList();
      usedWords.addAll(words100);
      if (pair.length == 1) {
        push(
          '"${cap(words100.first)} starts with the letter ${pair.first}," '
          'said the $hero.',
        );
      } else {
        push(
          '"${cap(words100[0])} starts with ${pair[0]}, and '
          '${words100[1]} starts with ${pair[1]}," said the $hero.',
        );
      }
    }

    // --- Body: a few short adventures with the hero -----------------------
    final focusWord = cap(_wordForLetter[letterList.first] ?? 'ball');
    // {objA}/{objB} are placeholders replaced with a correctly articulated
    // practice word ("an egg"), so the child's own words appear in the story.
    String fill(String t) => t
        .replaceAll('{hero}', 'the $hero')
        .replaceAll('{friend}', 'the $friend')
        .replaceAll('{objA}', withArticle(objectsList[0]))
        .replaceAll(
          '{objB}',
          objectsList.length > 1
              ? withArticle(objectsList[1])
              : withArticle(objectsList[0]),
        )
        .replaceAll('{focusWord}', 'a $focusWord');

    List<String> bodyTemplates() {
      if (level == 1) {
        return [
          'The $hero met {friend} beside the big tree.',
          '{hero} and {friend} sang a happy song together.',
          '{hero} found {objA} and hid it in the grass.',
          '{hero} waved to {friend} and went home.',
        ];
      } else if (level == 2) {
        return [
          'At noon, the $hero met {friend} down by the big tree.',
          '{friend} showed {hero} {objA} from their bag.',
          'Together they stashed {objB} in a mossy hiding spot.',
          'After the fun, {hero} and {friend} shared a happy snack.',
        ];
      } else {
        return [
          'Across the busy street, the $hero helped {friend} find its way '
              'back to the garden.',
          'Every turn of the path brought a new sight: {focusWord}, a tall '
              'tree, and a quiet pond.',
          'Then {friend} spotted {objA} - and just past it, {objB}.',
          '{friend} smiled and thanked {hero} for the kind help.',
          'By evening, the $hero had made a brand-new friend and a happy '
              'memory to keep forever.',
        ];
      }
    }

    final templates = bodyTemplates();
    final bodyCount = level == 1
        ? 2
        : level == 2
        ? 3
        : 4;
    // The hero always finds at least one of its practice words, so the
    // templates that reference the woven objects are guaranteed a slot and
    // the rest of the quota is filled at random.
    int indexWith(String marker) =>
        templates.indexWhere((t) => t.contains(marker));
    final must = <int>{
      if (objectsList.isNotEmpty) indexWith('{objA}'),
      if (objectsList.length > 1) indexWith('{objB}'),
    }.where((i) => i >= 0).toList();
    final picks = <int>[...must];
    final remaining = List<int>.generate(templates.length, (i) => i)
      ..removeWhere((i) => must.contains(i))
      ..shuffle(rng);
    for (var i = 0; picks.length < bodyCount && i < remaining.length; i++) {
      picks.add(remaining[i]);
    }
    picks.shuffle(rng);
    for (final i in picks) {
      push(fill(templates[i]));
    }

    push('On the way home, the $hero felt happy, strong, and so very proud.');

    // --- Closing ------------------------------------------------------------
    if (level == 1) {
      push('The end. What a lovely day!');
    } else if (level == 2) {
      push('They waved good night and promised to meet again tomorrow.');
    } else {
      push(
        'And from that day on, every morning started with a brand-new '
        'adventure under the same bright sky.',
      );
    }

    // --- Title ---------------------------------------------------------------
    final titles = <String>[
      'The day of the $hero',
      'A brave little $hero',
      '$hero and the great adventure',
      'The $hero goes exploring',
    ];
    final title = cap(titles[rng.nextInt(titles.length)]);

    return Story(
      title: title,
      level: level,
      sentences: sentences,
      focusLetters: lettersNotEmptyOr(troubleLetters),
      usedWords: usedWords.toList(),
    );
  }

  static String _articleFor(String word) {
    return 'a${'aeiou'.contains(word.isNotEmpty ? word[0] : '') ? 'n' : ''}';
  }

  static Set<String> lettersNotEmptyOr(Set<String> letters) =>
      letters.isEmpty ? const {'b', 'd'} : letters;
}
