import 'dart:math';

/// One generated AI story, ready for the StoryScreen.
class Story {
  final String title;
  final int level; // 1 = beginner, 2 = developing, 3 = confident
  final List<String> sentences;
  final Set<String> focusLetters;
  final List<String> usedWords;
  final String hero;
  final String location;

  Story({
    required this.title,
    required this.level,
    required this.sentences,
    required this.focusLetters,
    required this.usedWords,
    required this.hero,
    required this.location,
  });
}

/// On-device story generator.
///
/// Turns the child's practice words and their recurring trouble letters into
/// a short, readable story with a proper beginning, middle and end. It draws
/// from large hero, location, opener, plot, twist and closer pools so every
/// story reads differently, weaves in the child's practice words naturally,
/// and gives each trouble letter a "letter spotlight" sentence.
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

  /// Animate heroes only - a story whose hero is an object from the practice
  /// words ("a little garden went out to explore the town") reads as
  /// nonsense. Practice words are woven in as things the hero discovers.
  static const List<String> animateHeroes = [
    'cat', 'dog', 'fox', 'bear', 'mouse', 'rabbit', 'goat', 'owl', 'pig',
    'frog', 'pony', 'duck', 'dragon', 'panda', 'whale', 'lion',
    'tiger', 'wolf', 'deer', 'sheep', 'llama', 'koala', 'zebra', 'otter',
    'beaver', 'hare', 'kitten', 'puppy', 'chick', 'hen', 'swan', 'crane',
    'eagle', 'hawk', 'parrot', 'penguin', 'seal', 'walrus', 'dolphin',
    'shark', 'octopus', 'snail', 'tortoise', 'lizard', 'gecko', 'toad',
    'hamster', 'gerbil', 'camel', 'hippo', 'rhino', 'giraffe', 'elephant',
    'monkey', 'gorilla', 'lemur', 'bat', 'hedgehog', 'squirrel', 'raccoon',
    'badger', 'moose', 'buffalo', 'bison', 'crab', 'lobster', 'ant', 'bee',
    'beetle', 'ladybug', 'firefly', 'unicorn', 'pixie', 'elf', 'gnome',
    'troll', 'giant', 'alien', 'robot', 'dinosaur', 'worm',
  ];

  /// Settings the adventure can take place in.
  static const List<String> locations = [
    'town', 'forest', 'beach', 'mountains', 'meadow', 'market', 'castle',
    'garden', 'desert', 'jungle', 'swamp', 'island', 'lighthouse', 'farm',
    'pond', 'river', 'bakery', 'library', 'museum', 'circus', 'shipyard',
    'hotel', 'spaceport', 'ice kingdom', 'treehouse park', 'observatory',
    'cave', 'orchard', 'harbor', 'savanna', 'canyon', 'glacier', 'volcano',
    'waterfall', 'railroad station', 'campground', 'moon', 'underwater city',
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
    String pick(List<String> pool) => pool[rng.nextInt(pool.length)];

    // Practice words that aren't obviously junk.
    final practice = words
        .where((w) => w.trim().isNotEmpty)
        .map((w) => w.trim().toLowerCase())
        .toList();

    // Hero, friend and location are all drawn from large pools.
    final hero = pick(animateHeroes);
    var friend = pick(animateHeroes);
    while (friend == hero) {
      friend = pick(animateHeroes);
    }
    final location = pick(locations);
    final article = _articleFor(hero);
    String withArticle(String noun) => '${_articleFor(noun)} $noun';

    // Object words the hero can discover on the adventure. Short single
    // words read best; fall back to a small built-in set when there are none.
    final objectPool = practice
        .where((w) => !animateHeroes.contains(w) && w.length <= 10)
        .toList();
    final fallbackObjects = const ['ball', 'book', 'shell', 'feather', 'stone'];
    final candidates = objectPool.isNotEmpty ? objectPool : fallbackObjects;
    final woven = <String>{};
    while (woven.length < 2 && woven.length < candidates.length) {
      woven.add(candidates[rng.nextInt(candidates.length)]);
    }
    final objectsList = woven.toList();

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

    // --- Opening: a different opener for every story and level ------------
    final openers = switch (level) {
      1 => [
          'This is a story about {aHero}.',
          'Once there was {aHero} who lived near the {location}.',
          'Meet {aHero}, the bravest little friend in the {location}.',
          'A little {bareHero} had a big heart and a tiny home near the {location}.',
          'This is the tale of {aHero} and one very special day.',
          'In the {location}, everyone knew {aHero} was the kindest of all.',
        ],
      2 => [
          'One fine day, a little {bareHero} went out to explore the {location}.',
          'In a busy {location}, {aHero} found a mystery waiting to be solved.',
          'The morning sparkled as {aHero} padded out into the {location}.',
          'By the edge of the {location}, {aHero} met {aFriend} with a big plan.',
          'Everyone in the {location} knew it would be a big day for {aHero}.',
          'One morning, {aHero} woke up with a wonderful idea.',
        ],
      _ => [
          'Long ago, in a cozy corner near the {location}, a clever {bareHero} woke to a shining morning.',
          'Across the {location}, a brave {bareHero} set out on the most important journey yet.',
          'When the first light touched the {location}, {aHero} began a day no one would forget.',
          'In the heart of the {location}, a wise {bareHero} listened to a gentle riddle on the wind.',
          'High above the {location}, a young {bareHero} dreamed of something extraordinary.',
        ],
    };

    // --- Letter spotlight: each focus letter with a matching word ---------
    final spotOpeners = switch (level) {
      1 => [
          'Today the letters we practice are {letters}.',
          'We are learning the letters {letters} today!',
        ],
      2 => [
          '"The letters we practice today are {letters}," said the hero.',
          '"{letters} are the letters of the day," announced the hero.',
        ],
      _ => [
          '"Every letter wakes up its own sound," the hero explained. "Today we listen for {letters}."',
          '"Letters are like little songs," said the hero. "Today we sing {letters}."',
        ],
    };

    // --- Body: a few short adventures with the hero -----------------------
    final bodyTemplates = switch (level) {
      1 => [
          '{hero} met {friend} beside the {location}.',
          '{hero} and {friend} sang a happy song together.',
          '{hero} found {objA} and hid it in the grass.',
          '{hero} showed {objA} to {friend}.',
          '{friend} gave {hero} {objB} as a present.',
          '{hero} hopped, {friend} bounced, and they laughed all afternoon.',
          'Then {hero} heard a tiny sound under {objB}.',
          '{hero} and {friend} built a little fort near the {location}.',
        ],
      2 => [
          'At noon, {hero} met {friend} down by the {location}.',
          '{friend} showed {hero} {objA} from their bag.',
          'Together they stashed {objB} in a mossy hiding spot.',
          'After the fun, {hero} and {friend} shared a happy snack.',
          '{hero} led the way past tall trees toward the {location}.',
          'A gust of wind swept up {objA}, and {friend} chased it with a grin.',
          'That afternoon they traded secrets under a curly old tree.',
          '{hero} promised {friend} that the {location} held one more surprise.',
        ],
      _ => [
          'Across the busy street, {hero} helped {friend} find its way back to the {location}.',
          'Every turn of the path brought a new sight: {focusWord}, a tall tree, and a quiet pond.',
          'Then {friend} spotted {objA} - and just past it, {objB}.',
          '{friend} smiled and thanked {hero} for the kind help.',
          'By evening, {hero} had made a brand-new friend and a memory to keep forever.',
          'As dusk fell, {hero} and {friend} traced a map of all they had seen near the {location}.',
          'A hidden trail led them to {objA}, resting where no one had looked for years.',
          '{hero} whispered to {friend}, "Every place has a story - today the {location} told us ours."',
        ],
    };

    // --- Twist endings keep even familiar adventures feeling fresh ---------
    final twists = [
      'Then came the surprise: {friend} had been planning this adventure all along.',
      'And the best secret of all was that the {location} was the perfect place for {hero} and {friend}.',
      'Right at the end, {hero} discovered that the real treasure was {friend}.',
      'Everyone cheered, because the day had turned out better than any dream.',
      'At the last second, {hero} found a tiny note that said: "You did it!"',
    ];

    // --- Closers ----------------------------------------------------------
    final closers = switch (level) {
      1 => [
          'The end. What a happy day!',
          'Then {hero} went home, happy and proud.',
          'Hooray for {hero}! What a lovely day!',
        ],
      2 => [
          'They waved good night and promised to meet again tomorrow.',
          'At home, {hero} told everyone about the wonderful day.',
          'And that night, {hero} smiled and dreamed of the {location}.',
          'What a perfect day - and tomorrow would bring more fun.',
        ],
      _ => [
          'And from that day on, every morning started with a brand-new adventure under the same bright sky.',
          '{hero} and {friend} knew that the {location} would always be their special place.',
          'Somewhere under the stars, {hero} made a wish and smiled at the sky.',
          'And so the {location} kept its magic, waiting for the next brave little {bareHero}.',
        ],
    };

    // --- Titles -----------------------------------------------------------
    final titles = [
      'The day of the {aHero}',
      'A brave little {bareHero}',
      '{bareHero} and the great adventure',
      'The {bareHero} goes exploring',
      '{bareHero} in the {location}',
      'A secret in the {location}',
      '{bareHero} and {bareFriend} to the rescue',
      'The mystery of the {location}',
      'The big surprise for {bareHero}',
      'One wonderful day in the {location}',
      '{bareFriend} and the magic of the {location}',
      'The {bareHero} who found a treasure',
      'Adventures at the {location}',
      '{bareHero}, little but brave',
      'The best day of {bareHero}',
      'A journey through the {location}',
    ];

    String focusWordFor(List<String> letters) =>
        _wordForLetter[letters.first] ?? 'ball';

    // Marker substitution so every template reads naturally.
    String fill(String t) {
      return t
          .replaceAll('{aHero}', '$article $hero')
          .replaceAll('{bareHero}', hero)
          .replaceAll('{friend}', 'the $friend')
          .replaceAll('{aFriend}', '${_articleFor(friend)} $friend')
          .replaceAll('{bareFriend}', friend)
          .replaceAll('{hero}', 'the $hero')
          .replaceAll('{location}', location)
          .replaceAll('{objA}', withArticle(objectsList[0]))
          .replaceAll(
            '{objB}',
            objectsList.length > 1
                ? withArticle(objectsList[1])
                : withArticle(objectsList[0]),
          )
          .replaceAll('{focusWord}', withArticle(focusWordFor(letterList)));
    }

    // Opening.
    push(fill(pick(openers)));

    // Letter spotlight: always say which letters we practice, then pair each
    // with a real word that starts with it.
    push(
      fill(pick(spotOpeners)).replaceAll(
        '{letters}',
        letterList.join(' and '),
      ),
    );

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
          'said the hero.',
        );
      } else {
        push(
          '"${cap(words100[0])} starts with ${pair[0]}, and '
          '${words100[1]} starts with ${pair[1]}," said the hero.',
        );
      }
    }

    // Body: always include the practice objects and the friend so nothing we
    // promise in `usedWords` is left out, then fill the rest at random.
    final bodyCount = level == 1 ? 3 : level == 2 ? 3 : 4;
    int indexWith(String marker) =>
        bodyTemplates.indexWhere((t) => t.contains(marker));
    final must = <int>{
      if (objectsList.isNotEmpty) indexWith('{objA}'),
      if (objectsList.length > 1) indexWith('{objB}'),
      indexWith('{friend}'),
    }.where((i) => i >= 0).toList();
    final picks = <int>[...must];
    final remaining = List<int>.generate(bodyTemplates.length, (i) => i)
      ..removeWhere((i) => must.contains(i))
      ..shuffle(rng);
    for (var i = 0; picks.length < bodyCount && i < remaining.length; i++) {
      picks.add(remaining[i]);
    }
    picks.shuffle(rng);
    for (final i in picks) {
      push(fill(bodyTemplates[i]));
    }

    // A surprise twist every now and then.
    if ((level == 2 || level == 3) && rng.nextBool()) {
      push(fill(pick(twists)));
    }

    push('On the way home, {hero} felt happy, strong, and so very proud.');

    // Closing.
    push(fill(pick(closers)));

    // Title.
    final title = cap(fill(pick(titles)));

    return Story(
      title: title,
      level: level,
      sentences: sentences,
      focusLetters: lettersNotEmptyOr(troubleLetters),
      usedWords: usedWords.toList(),
      hero: hero,
      location: location,
    );
  }

  static String _articleFor(String word) {
    return 'a${'aeiou'.contains(word.isNotEmpty ? word[0] : '') ? 'n' : ''}';
  }

  static Set<String> lettersNotEmptyOr(Set<String> letters) =>
      letters.isEmpty ? const {'b', 'd'} : letters;
}