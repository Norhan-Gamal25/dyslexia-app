import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import '../services/gamification_service.dart';
import '../services/letter_analysis.dart';
import '../services/session_service.dart';
import '../services/speech_service.dart';
import '../widgets/kid_feedback.dart';

class SpeechPatternScreen extends StatefulWidget {
  const SpeechPatternScreen({super.key});

  @override
  State<SpeechPatternScreen> createState() => _SpeechPatternScreenState();
}

class _SpeechPatternScreenState extends State<SpeechPatternScreen> {
  static const int _maxAutoRetries = 3;

  final SpeechService _speech = SpeechService.instance;
  String _paragraph = 'Loading paragraph...';
  String _result = '';
  String _status = 'Preparing speech...';
  bool _listening = false;
  bool _speechReady = false;

  /// Latest recognized words, kept so the analysis can be shown even when
  /// the engine ends the session without a clean final result.
  String _lastWords = '';

  /// Callback registration token returned by [SpeechService.attach]; passed
  /// back to [SpeechService.detach] on dispose so this screen never keeps -
  /// or loses - the shared speech callbacks while another speech screen is
  /// pushed on top of it.
  int? _speechToken;

  /// How many automatic re-listens remain for the current attempt. Devices
  /// with a busy/noisy recognizer often need one or two retries before they
  /// transcribe anything; this lets us retry without looping forever and is
  /// reset to full every time the child taps the button.
  int _autoRetries = 0;

  bool _retrying = false;

  /// The scored comparison for the current session, kept so the build can
  /// render a proper analysis card (accuracy + the exact letter mixes ups
  /// such as "e / o"), not just a blob of text.
  WordComparisonResult? _comparison;
  String _spoken = '';

  @override
  void initState() {
    super.initState();
    _loadParagraph();
    _initSpeech();
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
          ? 'Press the button and read the paragraph aloud'
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

  /// Manual button tap. Resets the retry budget so endless sessions never
  /// accumulate across taps.
  void _onStartPressed() {
    _autoRetries = 0;
    _startListening();
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

  /// If the session took place without a final result but we did pick up
  /// some words, show the analysis anyway so the child always gets feedback.
  Future<void> _loadParagraph() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('practicepara')
          .doc('speechpat')
          .get()
          .timeout(const Duration(seconds: 5));
      final data = doc.data();
      if (data != null && data.isNotEmpty) {
        final values = data.values.map((v) => v.toString()).toList();
        final selected =
            values[DateTime.now().millisecondsSinceEpoch % values.length];
        if (mounted) setState(() => _paragraph = selected);
      }
    } catch (e) {
      if (mounted) setState(() => _paragraph = 'Error loading paragraph');
    }
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
    });
    try {
      _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          _lastWords = result.recognizedWords;
          if (result.finalResult) {
            if (_listening) setState(() => _listening = false);
            final comparison = LetterAnalysis.compare(
              _paragraph,
              result.recognizedWords,
            );
            _saveSession(comparison);
            setState(() {
              _comparison = comparison;
              _spoken = result.recognizedWords;
              _result = _formatResult(comparison, result.recognizedWords);
            });
          } else {
            setState(
              () => _status = 'Listening... "${result.recognizedWords}"',
            );
          }
        },
        localeId: locale,
        listenFor: const Duration(seconds: 20),
      );
    } catch (e) {
      setState(() {
        _listening = false;
        _status = 'Could not start listening: $e';
      });
    }
  }

  /// Runs once the engine has stopped listening. If we heard words, score
  /// them; otherwise try a couple more times before giving up gently.
  void _onSessionEnded() {
    if (!mounted || _listening) return;
    if (_lastWords.isNotEmpty && _comparison == null) {
      final comparison = LetterAnalysis.compare(_paragraph, _lastWords);
      _saveSession(comparison);
      setState(() {
        _comparison = comparison;
        _spoken = _lastWords;
        _result = _formatResult(comparison, _lastWords);
      });
      return;
    }
    if (_result.isEmpty && _autoRetries < _maxAutoRetries) {
      _autoRetries++;
      setState(
        () => _status = 'I did not quite catch that.\nListening again...',
      );
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        _startListening();
      });
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _listening = false;
      _status = 'Press the button and read the paragraph aloud';
    });
    _onSessionEnded();
  }

  Future<void> _saveSession(WordComparisonResult comparison) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await SessionService.instance.saveSession(
        childUid: uid,
        type: 'speech',
        result: comparison,
      );
    } catch (_) {
      // Session history is a bonus for the parent dashboard - don't block
      // the child if saving it fails (e.g. offline).
    }
    try {
      final reward = await GamificationService.instance.recordExercise(
        childUid: uid,
        type: 'speech',
        accuracy: comparison.accuracy,
      );
      if (mounted && reward != null) celebrate(context, reward);
    } catch (_) {
      // Points are a nice extra - never interrupt practice on failures.
    }
  }

  String _formatResult(WordComparisonResult comparison, String spoken) {
    final buffer = StringBuffer()
      ..writeln('Accuracy: ${comparison.accuracy.toStringAsFixed(1)}%')
      ..writeln(
        'Correct words: ${comparison.correctWords}/${comparison.totalWords}',
      );
    if (comparison.confusions.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(
        'Letters to watch: '
        '${comparison.confusions.keys.map(LetterAnalysis.labelFor).join(', ')}',
      );
    }
    buffer
      ..writeln()
      ..writeln('Spoken:')
      ..write(spoken);
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Speech Pattern')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Read this paragraph aloud:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(_paragraph, style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _speechReady
                    ? (_listening ? _stopListening : _onStartPressed)
                    : null,
                icon: Icon(_listening ? Icons.stop : Icons.mic),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child:
                      Text(_listening ? 'Stop Listening' : 'Start Speaking'),
                ),
              ),
              const SizedBox(height: 16),
              if (_comparison != null)
                _AnalysisCard(
                  comparison: _comparison!,
                  spoken: _spoken,
                  target: _paragraph,
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loadParagraph,
                icon: const Icon(Icons.refresh),
                label: const Text('New Paragraph'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders the verdict for a speech session: the accuracy, which letter
/// pairs the child mixed up (e.g. "e / o") and the exact words spoken.
class _AnalysisCard extends StatelessWidget {
  final WordComparisonResult comparison;
  final String spoken;
  final String target;

  const _AnalysisCard({
    required this.comparison,
    required this.spoken,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final confusions = comparison.confusions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final missing = LetterAnalysis.missingLetters(target, spoken);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Accuracy: ${comparison.accuracy.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${comparison.correctWords} of ${comparison.totalWords} '
              'word${comparison.totalWords == 1 ? '' : 's'} correct',
              style: const TextStyle(fontSize: 14),
            ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Missing letters:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final letter in missing)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFA5D6A7)),
                      ),
                      child: Text(
                        letter.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (confusions.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'You mix up these letters:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              for (final entry in confusions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBE9E7),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFF8A80)),
                        ),
                        child: Text(
                          LetterAnalysis.labelFor(entry.key),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFFC62828),
                          ),
                        ),
                      ),
                      if (entry.value > 1) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${entry.value}×',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                LetterAnalysis.exerciseFor(confusions.first.key),
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
            if (spoken.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'You said:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(spoken, style: const TextStyle(fontSize: 16)),
            ],
          ],
        ),
      ),
    );
  }
}
