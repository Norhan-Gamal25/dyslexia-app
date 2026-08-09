import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import '../services/gamification_service.dart';
import '../services/letter_analysis.dart';
import '../services/session_service.dart';
import '../services/speech_service.dart';
import '../widgets/kid_feedback.dart';

class TrainSpeechScreen extends StatefulWidget {
  const TrainSpeechScreen({super.key});

  @override
  State<TrainSpeechScreen> createState() => _TrainSpeechScreenState();
}

class _TrainSpeechScreenState extends State<TrainSpeechScreen> {
  static const int _maxAutoRetries = 3;

  final SpeechService _speech = SpeechService.instance;
  String _word = 'Loading...';
  bool _listening = false;
  bool _speechReady = false;
  String _status = 'Preparing speech...';

  /// Latest recognized words, kept so the analysis can be shown even when the
  /// engine ends the session without a clean final result.
  String _lastWords = '';

  /// Callback registration token returned by [SpeechService.attach]; passed
  /// back to [SpeechService.detach] on dispose so this screen never keeps -
  /// or loses - the shared speech callbacks while another speech screen is
  /// pushed on top of it.
  int? _speechToken;

  /// The scored result for the current attempt, plus the raw spoken text it
  /// was computed from.
  WordComparisonResult? _comparison;
  String _spoken = '';

  /// How many automatic re-listens remain for the current attempt. Devices
  /// with a busy/noisy recognizer often need one or two retries before they
  /// transcribe anything; this lets us retry without looping forever and is
  /// reset to full every time the child taps the button.
  int _autoRetries = 0;

  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _loadWord();
  }

  @override
  void dispose() {
    final token = _speechToken;
    if (token != null) SpeechService.instance.detach(token);
    super.dispose();
  }

  Future<void> _initSpeech() async {
    var available = false;
    try {
      final (token, ready) = await _speech.attach(
        onStatus: _handleStatus,
        onError: _handleError,
      );
      _speechToken = token;
      available = ready;
    } catch (_) {
      available = false;
    }
    if (!mounted) return;
    setState(() {
      _speechReady = available;
      _status = available
          ? 'Press the button and say the word'
          : 'Speech recognition is not available on this device.\n'
                'Install the Google app / update Google Play services.';
    });
  }

  void _handleError(SpeechRecognitionError error) {
    if (!mounted || _retrying) return;
    setState(() {
      _listening = false;
      _status = 'Speech error: ${error.errorMsg}';
    });
    // A no-match / busy / timeout error can be recovered from by re-listening;
    // otherwise the engine normally follows with a status notification where
    // [onSessionEnded] also retries. Error-triggered retries share the same
    // budget so we can never loop forever.
    final message = error.errorMsg;
    final recoverable = message.contains('no_match') ||
        message.contains('error_7') ||
        message.contains('busy') ||
        message.contains('timeout') ||
        message.contains('audio');
    if (!recoverable || _autoRetries >= _maxAutoRetries) return;
    _autoRetries++;
    _retrying = true;
    setState(() => _status = 'Did not catch that.\nListening again...');
    Future.delayed(const Duration(milliseconds: 800), () {
      _retrying = false;
      if (!mounted) return;
      _startListening();
    });
  }

  void _handleStatus(String status) {
    if (!mounted) return;
    switch (status) {
      case 'listening':
        setState(() {
          _listening = true;
          _status = 'Listening...';
        });
        break;
      case 'done':
      case 'notListening':
      case 'error':
        setState(() {
          _listening = false;
          if (_status == 'Listening...' || _status == 'Starting…') {
            _status = 'Listening finished. Press the button to try again.';
          }
        });
        _onSessionEnded();
        break;
    }
  }

  /// Manual button tap. Resets the retry budget so endless sessions never
  /// accumulate across taps.
  void _onSpeakPressed() {
    _autoRetries = 0;
    _startListening();
  }

  Future<void> _loadWord() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('practicepara')
          .doc('words')
          .get()
          .timeout(const Duration(seconds: 5));
      final data = doc.data();
      if (data != null && data.isNotEmpty) {
        final words = data.values.map((v) => v.toString()).toList();
        final selected =
            words[DateTime.now().millisecondsSinceEpoch % words.length];
        if (mounted) {
          setState(() {
            _word = selected;
            _resetResult();
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _word = 'No words loaded');
    }
  }

  void _resetResult() {
    _comparison = null;
    _spoken = '';
  }

  Future<void> _startListening() async {
    if (!_speechReady) return;
    // A recognizer left "busy" by a previous no-match silently swallows the
    // next listen() call. Cancelling first ensures this attempt actually starts.
    await _speech.cancelAndWait();
    if (!mounted) return;
    final locale = await _speech.resolveEnglishLocale();
    if (!mounted) return;
    setState(() {
      _listening = true;
      _status = 'Listening...';
      _lastWords = '';
      _resetResult();
    });
    try {
      _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          _lastWords = result.recognizedWords;
          if (result.finalResult) {
            if (_listening) setState(() => _listening = false);
            _finish(result.recognizedWords);
          } else {
            setState(
              () => _status = 'Listening... "${result.recognizedWords}"',
            );
          }
        },
        localeId: locale,
        listenFor: const Duration(seconds: 10),
      );
    } catch (e) {
      setState(() {
        _listening = false;
        _status = 'Could not start listening: $e';
      });
    }
  }

  /// Runs once the engine has stopped listening. If we heard a word, score it;
  /// otherwise try a couple more times before giving up gently.
  void _onSessionEnded() {
    if (!mounted || _listening) return;
    if (_lastWords.trim().isNotEmpty) {
      _finish(_lastWords);
      return;
    }
    if (_autoRetries < _maxAutoRetries) {
      _autoRetries++;
      setState(
        () => _status = 'I did not quite catch that.\nListening again...',
      );
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        _startListening();
      });
      return;
    }
    _autoRetries = 0;
    _finish('');
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _listening = false;
      _status = 'Press the button and say the word';
    });
    _onSessionEnded();
  }

  /// Scores whatever words we picked up, or shows a gentle hint when the
  /// engine heard nothing at all.
  void _finish(String spoken) {
    if (!mounted) return;
    final trimmed = spoken.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _comparison = null;
        _spoken = '';
        _status = 'Could not hear you. Take a breath and try again.';
      });
      return;
    }
    final comparison = LetterAnalysis.compare(_word, trimmed);
    final accuracy = _letterAccuracy(_word, trimmed);
    setState(() {
      _comparison = comparison;
      _spoken = trimmed;
      if (comparison.accuracy >= 100 || accuracy >= 100) {
        _status = 'Great job!';
      } else if (comparison.confusions.isNotEmpty) {
        _status = 'Almost! Watch your letters below.';
      } else {
        _status = 'Nice try - keep practicing!';
      }
    });
    _award(comparison, accuracy);
  }

  /// Letter-level accuracy (positional). More meaningful than word-level
  /// accuracy when the target is a single word.
  double _letterAccuracy(String target, String spoken) {
    final t = target.toLowerCase();
    final s = spoken.toLowerCase();
    if (t.isEmpty) return 0;
    var match = 0;
    for (var i = 0; i < s.length && i < t.length; i++) {
      if (s[i] == t[i]) match++;
    }
    return (match / t.length * 100).roundToDouble();
  }

  /// Saves the session for the parent dashboard and hands out points + badges.
  Future<void> _award(WordComparisonResult comparison, double accuracy) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final forDashboard = WordComparisonResult(
      correctWords: comparison.correctWords,
      totalWords: comparison.totalWords,
      accuracy: accuracy,
      confusions: comparison.confusions,
    );
    try {
      await SessionService.instance.saveSession(
        childUid: uid,
        type: 'train',
        result: forDashboard,
      );
    } catch (_) {
      // Session history is a bonus for the parent dashboard - don't block
      // the child if saving it fails (e.g. offline).
    }
    try {
      final reward = await GamificationService.instance.recordExercise(
        childUid: uid,
        type: 'train',
        accuracy: accuracy,
      );
      if (mounted && reward != null) celebrate(context, reward);
    } catch (_) {
      // Points are a nice extra - never interrupt practice on failures.
    }
  }

  /// Builds a color-coded letter row for the spoken word against the target:
  /// green = correct, orange = a letter that was mixed up (e.g. e for o),
  /// red = an extra letter beyond the target.
  TextSpan _letterSpan(String letter, int index) {
    final target = _word.toLowerCase();
    Color color;
    if (index < target.length && letter == target[index]) {
      color = const Color(0xFF2E7D32);
    } else if (index < target.length) {
      color = const Color(0xFFEF6C00);
    } else {
      color = const Color(0xFFC62828);
    }
    return TextSpan(
      text: letter,
      style: TextStyle(
        color: color,
        fontSize: 30,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      ),
    );
  }

  Widget _analysisCard() {
    final comparison = _comparison;
    final spoken = _spoken.toLowerCase();
    final missing = LetterAnalysis.missingLetters(_word, spoken);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Accuracy: ${comparison!.accuracy.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${comparison.correctWords} of ${comparison.totalWords} '
              'word${comparison.totalWords == 1 ? '' : 's'} correct',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'You said:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                children: [
                  for (var i = 0; i < spoken.length; i++)
                    _letterSpan(spoken[i], i),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Target: ${_word.toLowerCase()}',
              style: const TextStyle(fontSize: 16),
            ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Missing letters:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                missing.map((l) => l.toUpperCase()).join(', '),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFC62828),
                ),
              ),
            ],
            if (comparison.confusions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Letters to watch: '
                '${comparison.confusions.keys.map(LetterAnalysis.labelFor).join(', ')}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                LetterAnalysis.exerciseFor(comparison.confusions.keys.first),
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Train Speech')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Say this word:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                _word,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _speechReady
                    ? (_listening ? _stopListening : _onSpeakPressed)
                    : null,
                icon: Icon(_listening ? Icons.stop : Icons.mic),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(_listening ? 'Stop' : 'Speak'),
                ),
              ),
              const SizedBox(height: 24),
              if (_comparison != null) _analysisCard(),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loadWord,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Another Word'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}