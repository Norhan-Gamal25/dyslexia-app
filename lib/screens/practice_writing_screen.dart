import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Ink;
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';
import '../services/gamification_service.dart';
import '../services/letter_analysis.dart';
import '../services/practice_words_service.dart';
import '../services/session_service.dart';
import '../widgets/kid_feedback.dart';

class PracticeWritingScreen extends StatefulWidget {
  const PracticeWritingScreen({super.key});

  @override
  State<PracticeWritingScreen> createState() => _PracticeWritingScreenState();
}

class _PracticeWritingScreenState extends State<PracticeWritingScreen> {
  final List<List<Offset>> _strokes = [];
  List<Offset>? _currentStroke;
  DigitalInkRecognizer? _recognizer;
  String _word = 'Loading...';
  String _result = '';

  /// Size of the drawing pad, given to the recognizer as the coordinate
  /// space the strokes were drawn in. This lets ML Kit normalize the ink
  /// correctly, which noticeably improves accuracy for children's writing.
  Size _padSize = const Size(400, 300);

  @override
  void initState() {
    super.initState();
    _recognizer = DigitalInkRecognizer(languageCode: 'en-US');
    _loadWord();
  }

  Future<void> _loadWord() async {
    try {
      // Mix in the shared word bank plus anything the child has added by
      // scanning their own flashcards or books, so practice reflects both.
      final words = <String>[];
      final doc = await FirebaseFirestore.instance
          .collection('practicepara')
          .doc('words')
          .get()
          .timeout(const Duration(seconds: 5));
      final data = doc.data();
      if (data != null && data.isNotEmpty) {
        words.addAll(data.values.map((v) => v.toString()));
      }
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          final customWords = await PracticeWordsService.instance
              .getCustomWords(uid);
          words.addAll(customWords);
        } catch (_) {
          // Custom words are a bonus - don't block practice if they fail
          // to load (e.g. offline).
        }
      }
      if (words.isNotEmpty) {
        final selected =
            words[DateTime.now().millisecondsSinceEpoch % words.length];
        if (mounted) {
          setState(() {
            _word = selected;
            _result = '';
            _strokes.clear();
          });
        }
      } else if (mounted) {
        setState(() => _word = 'No words loaded');
      }
    } catch (e) {
      if (mounted) setState(() => _word = 'No words loaded');
    }
  }

  Ink _buildInk() {
    final ink = Ink();
    for (final stroke in _strokes) {
      final s = Stroke();
      for (int i = 0; i < stroke.length; i++) {
        s.points.add(
          StrokePoint(
            x: stroke[i].dx,
            y: stroke[i].dy,
            t: DateTime.now().millisecondsSinceEpoch.toInt() + i,
          ),
        );
      }
      ink.strokes.add(s);
    }
    return ink;
  }

  Future<void> _checkWriting() async {
    if (_strokes.isEmpty) {
      setState(() => _result = 'Please write something first');
      return;
    }
    final recognizer = _recognizer;
    if (recognizer == null) {
      setState(
        () => _result = 'Handwriting model is loading. Please try again.',
      );
      return;
    }
    setState(() => _result = 'Recognizing...');
    try {
      final modelManager = DigitalInkRecognizerModelManager();
      final downloaded = await modelManager.isModelDownloaded('en-US');
      if (!downloaded) {
        final ok = await modelManager.downloadModel('en-US');
        if (!ok) {
          setState(
            () => _result =
                'Could not download handwriting model. Check internet.',
          );
          return;
        }
      }
      final candidates = await recognizer.recognize(
        _buildInk(),
        context: DigitalInkRecognitionContext(
          writingArea: WritingArea(
            width: _padSize.width,
            height: _padSize.height,
          ),
        ),
      );
      if (candidates.isNotEmpty) {
        final recognized = candidates.first.text.trim();
        _award(recognized);
        setState(() => _result = _buildResult(recognized));
      } else {
        setState(
          () => _result = 'Could not recognize the writing. Please try again.',
        );
      }
    } catch (e) {
      setState(() => _result = 'Recognition failed: $e');
    }
  }

  /// Builds the feedback text for a recognized word: spoken/correct letter
  /// counts, any confused letter pairs, and a matching exercise.
  String _buildResult(String recognized) {
    final target = _word.toLowerCase();
    final written = recognized.toLowerCase();
    final buffer = StringBuffer()
      ..writeln('Written: $recognized')
      ..writeln('Target: $_word');

    if (written.isEmpty) {
      buffer.writeln(
        '\nCould not read your writing. Try again in a bright '
        'room and keep inside the box.',
      );
      return buffer.toString();
    }

    // Letter-level count (positional) - more informative than word-level
    // accuracy when the target is a single word.
    var correct = 0;
    for (var i = 0; i < written.length && i < target.length; i++) {
      if (written[i] == target[i]) correct++;
    }
    final compare = LetterAnalysis.compare(_word, written);
    final percent = target.isEmpty
        ? 0.0
        : (correct / target.length * 100).toStringAsFixed(0);
    buffer
      ..writeln()
      ..writeln('$correct of ${target.length} letters correct ($percent%)');
    if (compare.confusions.isNotEmpty) {
      buffer
        ..writeln(
          'Letters to watch: '
          '${compare.confusions.keys.map(LetterAnalysis.labelFor).join(', ')}',
        )
        ..writeln(LetterAnalysis.exerciseFor(compare.confusions.keys.first));
    } else if (compare.accuracy >= 100) {
      buffer.writeln('Perfect! Great writing.');
    }
    return buffer.toString();
  }

  /// Positional letter accuracy (0-100) for the recognized word against the
  /// target, used both for the on-screen feedback and for scoring points.
  double _letterAccuracy(String target, String written) {
    if (target.isEmpty) return 0;
    var correct = 0;
    for (var i = 0; i < written.length && i < target.length; i++) {
      if (written[i] == target[i]) correct++;
    }
    return correct / target.length * 100;
  }

  /// Saves the practice session for the parent dashboard and rewards the
  /// child with points/badges. Failures never interrupt the practice flow.
  Future<void> _award(String recognized) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final accuracy = _letterAccuracy(_word, recognized);
    try {
      await SessionService.instance.saveSession(
        childUid: uid,
        type: 'practice',
        result: LetterAnalysis.compare(_word, recognized),
      );
    } catch (_) {}
    try {
      final reward = await GamificationService.instance.recordExercise(
        childUid: uid,
        type: 'practice',
        accuracy: accuracy,
      );
      if (mounted && reward != null) celebrate(context, reward);
    } catch (_) {}
  }

  @override
  void dispose() {
    _recognizer?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Practice Writing')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Write this word:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _word,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _padSize = constraints.biggest;
                  return Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) {
                      setState(() {
                        _currentStroke = [event.localPosition];
                      });
                    },
                    onPointerMove: (event) {
                      final current = _currentStroke;
                      if (current != null) {
                        setState(() {
                          current.add(event.localPosition);
                        });
                      }
                    },
                    onPointerUp: (event) {
                      setState(() {
                        if (_currentStroke != null &&
                            _currentStroke!.isNotEmpty) {
                          _strokes.add(List.of(_currentStroke!));
                          _currentStroke = null;
                        }
                      });
                    },
                    onPointerCancel: (event) {
                      setState(() {
                        if (_currentStroke != null &&
                            _currentStroke!.isNotEmpty) {
                          _strokes.add(List.of(_currentStroke!));
                          _currentStroke = null;
                        }
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _DrawingPainter(_strokes, _currentStroke),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            if (_result.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _result,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _strokes.clear();
                      _currentStroke = null;
                      _result = '';
                    }),
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loadWord,
                    child: const Text('Next Word'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _checkWriting,
                    child: const Text('Check'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset>? current;
  _DrawingPainter(this.strokes, this.current);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length > 1) {
        final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
        for (final p in stroke.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
    if (current != null && current!.length > 1) {
      final path = Path()..moveTo(current!.first.dx, current!.first.dy);
      for (final p in current!.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) => true;
}
