import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Ink;
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';

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

  @override
  void initState() {
    super.initState();
    _recognizer = DigitalInkRecognizer(languageCode: 'en-US');
    _loadWord();
  }

  Future<void> _loadWord() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('practicepara')
          .doc('words')
          .get();
      final data = doc.data();
      if (data != null && data.isNotEmpty) {
        final words = data.values.map((v) => v.toString()).toList();
        final selected =
            words[DateTime.now().millisecondsSinceEpoch % words.length];
        if (mounted) {
          setState(() {
            _word = selected;
            _result = '';
            _strokes.clear();
          });
        }
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
        s.points.add(StrokePoint(
          x: stroke[i].dx,
          y: stroke[i].dy,
          t: DateTime.now().millisecondsSinceEpoch.toInt() + i,
        ));
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
      setState(() => _result = 'Handwriting model is loading. Please try again.');
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
              () => _result = 'Could not download handwriting model. Check internet.');
          return;
        }
      }
      final candidates = await recognizer.recognize(_buildInk());
      if (candidates.isNotEmpty) {
        final recognized = candidates.first.text;
        setState(() => _result = 'Written: $recognized\nTarget: $_word');
      } else {
        setState(() => _result = 'Could not recognize the writing. Please try again.');
      }
    } catch (e) {
      setState(() => _result = 'Recognition failed: $e');
    }
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
            const Text('Write this word:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(_word,
                style: const TextStyle(
                    fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: Listener(
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
                    if (_currentStroke != null && _currentStroke!.isNotEmpty) {
                      _strokes.add(List.of(_currentStroke!));
                      _currentStroke = null;
                    }
                  });
                },
                onPointerCancel: (event) {
                  setState(() {
                    if (_currentStroke != null && _currentStroke!.isNotEmpty) {
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
              ),
            ),
            const SizedBox(height: 12),
            if (_result.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_result,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500)),
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