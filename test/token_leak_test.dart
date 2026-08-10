import 'package:flutter_test/flutter_test.dart';
import 'package:verbix/services/story_generator.dart';

void main() {
  test('no raw placeholder tokens leak into generated text', () {
    final g = StoryGenerator();
    for (final level in [1, 2, 3]) {
      for (var seed = 0; seed < 25; seed++) {
        final s = g.generate(
          words: const ['cat', 'dog', 'ball', 'book'],
          troubleLetters: const {'b', 'd'},
          level: level,
          seed: seed,
        );
        final text = s.sentences.join('\n');
        expect(text, isNot(contains('{hero}')));
        expect(text, isNot(contains('{letters}')));
        expect(text, isNot(contains('{objA}')));
      }
    }
  });
}