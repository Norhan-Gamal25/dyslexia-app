import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/gamification_service.dart';
import '../services/session_service.dart';
import '../services/story_generator.dart';
import '../widgets/kid_feedback.dart';

/// AI Storytelling screen.
///
/// Generates a personalized story from the child's practice words and their
/// recurring trouble letters, adapted to their reading level. Supports a
/// read-along mode that highlights each word (and each focus letter) while
/// the text is read aloud, rendered in the OpenDyslexic font with wide,
/// dyslexia-friendly spacing.
class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key});

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  late Future<Story> _storyFuture;
  FlutterTts? _tts;
  int _wordIndex = 0;
  int _sentenceIndex = 0;
  bool _playing = false;
  String _status = '';

  /// null = auto (derived from session accuracy); otherwise the user has
  /// explicitly chosen a level 1-3.
  int? _selectedLevel;

  /// Guards against double-awarding points when a story is re-read; reset
  /// whenever a new story is generated.
  bool _awarded = false;

  @override
  void initState() {
    super.initState();
    _storyFuture = _loadStory();
    _initTts();
  }

  @override
  void dispose() {
    _tts?.stop();
    _tts = null;
    super.dispose();
  }

  Future<void> _initTts() async {
    final tts = FlutterTts();
    await tts.setLanguage('en-US');
    await tts.setSpeechRate(0.35);
    await tts.setPitch(1.0);
    await tts.setVolume(1.0);
    // Without this, speak() returns as soon as the text is queued instead of
    // waiting until that sentence has finished being spoken. Because we read
    // one sentence at a time, the engine would otherwise queue every sentence
    // at once and only the last one would actually be heard.
    await tts.awaitSpeakCompletion(true);
    // Find each spoken word's index as the engine reads it, so the
    // read-along highlight stays in sync with the audio.
    tts.setProgressHandler((text, startOffset, endOffset, word) {
      if (!mounted) return;
      final words = text.toLowerCase().split(RegExp(r'\s+'));
      var index = 0;
      var consumed = 0;
      for (var i = 0; i < words.length; i++) {
        final w = words[i];
        if (startOffset >= consumed && startOffset < consumed + w.length + 1) {
          index = i;
          break;
        }
        consumed += w.length + 1;
      }
      setState(() => _wordIndex = index);
    });
    tts.setCompletionHandler(() {
      if (!mounted) return;
      setState(() => _wordIndex = 0);
    });
    _tts = tts;
  }

  /// Gathers the child's practice words + session data, then generates a
  /// story personalized to their level and trouble letters.
  Future<Story> _loadStory() async {
    final sessions = await _fetchSessions();
    final average = _averageAccuracy(sessions);
    final confusions = _confusions(sessions);
    final words = await _loadPracticeWords();
    final level = _selectedLevel ?? StoryGenerator.levelFromAccuracy(average);
    final letters = StoryGenerator.lettersFromConfusions(confusions);
    return StoryGenerator().generate(
      words: words,
      troubleLetters: letters,
      level: level,
      seed: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<List<SessionResult>> _fetchSessions() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const [];
    try {
      return await SessionService.instance.fetchSessions(uid);
    } catch (_) {
      return const [];
    }
  }

  double? _averageAccuracy(List<SessionResult> sessions) {
    if (sessions.isEmpty) return null;
    final sum = sessions.fold<double>(0, (acc, s) => acc + s.accuracy);
    return sum / sessions.length;
  }

  Map<String, int> _confusions(List<SessionResult> sessions) {
    final confusions = <String, int>{};
    for (final s in sessions) {
      s.confusions.forEach((key, value) {
        confusions[key] = (confusions[key] ?? 0) + value;
      });
    }
    return confusions;
  }

  Future<List<String>> _loadPracticeWords() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('practicepara')
          .doc('words')
          .get()
          .timeout(const Duration(seconds: 5));
      final data = doc.data();
      if (data == null || data.isEmpty) return StoryGenerator.exampleWords;
      return data.values.map((v) => v.toString()).toList();
    } catch (_) {
      return StoryGenerator.exampleWords;
    }
  }

  Future<void> _stopPlayback() async {
    await _tts?.stop();
    _sentenceIndex = 0;
    _wordIndex = 0;
    if (mounted) {
      setState(() {
        _playing = false;
        _status = '';
      });
    }
  }

  Future<void> _newStory() async {
    await _tts?.stop();
    setState(() {
      _playing = false;
      _wordIndex = 0;
      _sentenceIndex = 0;
      _status = '';
      _awarded = false;
      _storyFuture = _loadStory();
    });
  }

  /// Rewards the child once for finishing a whole story. Failures never
  /// interrupt the reading flow.
  Future<void> _awardStory() async {
    if (_awarded) return;
    _awarded = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final reward = await GamificationService.instance.recordExercise(
        childUid: uid,
        type: 'story',
        accuracy: 0,
      );
      if (mounted && reward != null) celebrate(context, reward);
    } catch (_) {}
  }

  Future<void> _togglePlay(Story story) async {
    if (_playing) {
      await _stopPlayback();
      return;
    }
    final sentences = story.sentences;
    if (sentences.isEmpty) return;
    if (_tts == null) return;
    setState(() {
      _playing = true;
      _status = 'Reading…';
      _sentenceIndex = 0;
      _wordIndex = 0;
    });
    await _tts?.setLanguage('en-US');
    // Speak one sentence at a time; the progress handler keeps the
    // read-along highlight synced to each spoken word.
    for (var i = 0; i < sentences.length; i++) {
      if (!mounted || !_playing) return;
      setState(() {
        _sentenceIndex = i;
        _status = 'Reading…';
      });
      await _tts?.speak(sentences[i]);
      if (!mounted || !_playing) return;
      // A short pause after each sentence makes the read-along easier to
      // follow - sentences are spoken strictly one at a time thanks to
      // awaitSpeakCompletion(true).
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (i == sentences.length - 1 && mounted) {
        setState(() => _status = 'Finished');
        _awardStory();
      }
    }
    if (mounted && _playing) {
      setState(() {
        _playing = false;
        _wordIndex = 0;
        _sentenceIndex = 0;
      });
    }
  }

  /// Translates the current (sentence, word) position into the flat index
  /// used by the story reader's highlight.
  int _flatWordIndex(Story story) {
    if (!_playing) return -1;
    var offset = 0;
    for (var i = 0; i < _sentenceIndex; i++) {
      offset += story.sentences[i].split(RegExp(r'\s+')).length;
    }
    return offset + _wordIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Stories')),
      body: FutureBuilder<Story>(
        future: _storyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not build your story.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final story = snapshot.data!;
          final words = storyWords(story);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'OpenDyslexic',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _LevelChip(story.level, auto: _selectedLevel == null),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Focus letters: '
                            '${story.focusLetters.join(', ').toUpperCase()}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      initialValue: _selectedLevel,
                      decoration: const InputDecoration(
                        labelText: 'Story level',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Auto (from practice results)'),
                        ),
                        DropdownMenuItem<int?>(
                          value: 1,
                          child: Text('Level 1 — beginner'),
                        ),
                        DropdownMenuItem<int?>(
                          value: 2,
                          child: Text('Level 2 — developing'),
                        ),
                        DropdownMenuItem<int?>(
                          value: 3,
                          child: Text('Level 3 — confident'),
                        ),
                      ],
                      onChanged: (value) {
                        _stopPlayback();
                        setState(() {
                          _selectedLevel = value;
                          _storyFuture = _loadStory();
                        });
                      },
                    ),
                    const Divider(height: 24),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: _StoryReader(
                    words: words,
                    currentIndex: _flatWordIndex(story),
                    focusLetters: story.focusLetters,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_status.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _status,
                          style: const TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _togglePlay(story),
                          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                          label: Text(_playing ? 'Pause' : 'Read aloud'),
                        ),
                        const SizedBox(width: 12),
                        IconButton.filledTonal(
                          tooltip: 'New story',
                          onPressed: _newStory,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Splits a story into a flat list of tokens (words + punctuation).
List<String> storyWords(Story story) {
  final words = <String>[];
  for (final s in story.sentences) {
    words.addAll(s.split(RegExp(r'\s+')));
  }
  return words;
}

class _LevelChip extends StatelessWidget {
  final int level;
  final bool auto;
  const _LevelChip(this.level, {this.auto = false});

  @override
  Widget build(BuildContext context) {
    final label = level == 1
        ? 'Level 1'
        : level == 2
        ? 'Level 2'
        : 'Level 3';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        auto ? '$label · auto' : label,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: Colors.indigo,
        ),
      ),
    );
  }
}

/// Renders the story words in the OpenDyslexic font with wide spacing.
/// During read-along, the current word is highlighted and the currently
/// spoken focus letter is underlined to reinforce letter-sound recognition.
class _StoryReader extends StatelessWidget {
  final List<String> words;
  final int currentIndex; // -1 when not playing
  final Set<String> focusLetters;

  const _StoryReader({
    required this.words,
    required this.currentIndex,
    required this.focusLetters,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < words.length; i++)
            _wordSpan(words[i], i == currentIndex),
        ],
      ),
      style: const TextStyle(
        fontSize: 24,
        height: 1.9,
        letterSpacing: 0.6,
        wordSpacing: 4,
        fontFamily: 'OpenDyslexic',
        color: Colors.black87,
      ),
    );
  }

  InlineSpan _wordSpan(String word, bool isCurrent) {
    final firstLetter = word.isNotEmpty ? word[0].toLowerCase() : '';
    final isFocusWord =
        firstLetter.isNotEmpty && focusLetters.contains(firstLetter);

    return TextSpan(
      text: '$word ',
      style: TextStyle(
        backgroundColor: isCurrent
            ? const Color(0xFFFFF59D)
            : Colors.transparent,
        color: isCurrent
            ? Colors.black
            : isFocusWord
            ? const Color(0xFF7B1FA2)
            : Colors.black87,
        fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
        decoration: isCurrent && isFocusWord ? TextDecoration.underline : null,
        decorationThickness: isCurrent && isFocusWord ? 3.0 : null,
      ),
    );
  }
}
