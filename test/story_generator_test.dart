import 'package:flutter_test/flutter_test.dart';
import 'package:verbix/services/story_generator.dart';

void main() {
  const words = ['cat', 'dog', 'bird', 'tree', 'ball', 'book'];
  const letters = {'b', 'd'};
  final generator = StoryGenerator();

  test('generates a non-empty story for every level', () {
    for (var level = 1; level <= 3; level++) {
      final story = generator.generate(
        words: words,
        troubleLetters: letters,
        level: level,
        seed: 42,
      );
      expect(story.sentences, isNotEmpty, reason: 'level $level');
      expect(story.sentences.length, greaterThanOrEqualTo(4),
          reason: 'level $level');
    }
  });

  test('includes the child practice words in the story', () {
    final story = generator.generate(
      words: words,
      troubleLetters: letters,
      level: 2,
      seed: 7,
    );
    final text = story.sentences.join(' ').toLowerCase();
    expect(story.usedWords, isNotEmpty);
    for (final w in story.usedWords) {
      expect(text, contains(w), reason: 'word "$w" should appear');
    }
  });

  test('each focus letter shows up in at least one sentence', () {
    final story = generator.generate(
      words: words,
      troubleLetters: letters,
      level: 1,
      seed: 3,
    );
    final text = story.sentences.join(' ').toLowerCase();
    for (final letter in letters) {
      expect(text, contains(letter),
          reason: 'letter "$letter" should be mentioned');
    }
  });

  test('different seeds produce different stories', () {
    final a = generator.generate(
        words: words, troubleLetters: letters, level: 2, seed: 1);
    final b = generator.generate(
        words: words, troubleLetters: letters, level: 2, seed: 99);
    expect(a.sentences.join(' '), isNot(b.sentences.join(' ')));
  });

  test('hero is always an animate character, never a practice object', () {
    const inertWords = [
      'garden', 'tree', 'book', 'water', 'phone', 'wall', 'sky', 'door',
    ];
    for (var seed = 0; seed < 40; seed++) {
      final story = generator.generate(
        words: inertWords,
        troubleLetters: const {'b', 'd'},
        level: 2,
        seed: seed,
      );
      final intro = story.sentences.first.toLowerCase();
      expect(StoryGenerator.animateHeroes, contains(story.hero),
          reason: 'seed $seed: "$intro"');
      expect(inertWords, isNot(contains(story.hero)),
          reason: 'seed $seed: hero "$story.hero" must not be an object');
      expect(intro, contains(story.hero),
          reason: 'seed $seed: "$intro" should mention the hero "$story.hero"');
    }
  });

  test('stories vary widely across seeds', () {
    final seen = <String>{};
    for (var seed = 0; seed < 60; seed++) {
      final story = generator.generate(
        words: words,
        troubleLetters: letters,
        level: 2,
        seed: seed,
      );
      seen.add(story.title);
      seen.add(story.sentences.first);
    }
    expect(seen.length, greaterThanOrEqualTo(30),
        reason: 'expected a wide variety, got only $seen');
  });

  test('levelFromAccuracy maps accuracy ranges', () {
    expect(StoryGenerator.levelFromAccuracy(null), 2);
    expect(StoryGenerator.levelFromAccuracy(40), 1);
    expect(StoryGenerator.levelFromAccuracy(70), 2);
    expect(StoryGenerator.levelFromAccuracy(90), 3);
  });

  test('lettersFromConfusions extracts pair letters', () {
    const c = {'b-d': 3, 'p-q': 1};
    final result = StoryGenerator.lettersFromConfusions(c);
    expect(result, containsAll(['b', 'd']));
  });
}