import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/gamification_service.dart';
import '../services/letter_analysis.dart';
import '../services/session_service.dart';
import '../widgets/kid_feedback.dart';

/// Lets a child practice letter patterns on a real sentence without relying
/// on unreliable camera handwriting scanning: the app shows a paragraph and
/// the child types it, then every letter is compared against the target.
class WritingPatternScreen extends StatefulWidget {
  const WritingPatternScreen({super.key});

  @override
  State<WritingPatternScreen> createState() => _WritingPatternScreenState();
}

class _WritingPatternScreenState extends State<WritingPatternScreen> {
  String _paragraph = 'Loading paragraph...';
  final TextEditingController _typeController = TextEditingController();

  /// The scored comparison of the typed text, rendered as a rich analysis
  /// card (accuracy, confusion chips, missing letters, exercise).
  WordComparisonResult? _comparison;
  String _typedText = '';
  int _pickOffset = 0;

  @override
  void initState() {
    super.initState();
    _loadParagraph();
  }

  @override
  void dispose() {
    _typeController.dispose();
    super.dispose();
  }

  Future<void> _loadParagraph() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('practicepara')
          .doc('writingprac')
          .get()
          .timeout(const Duration(seconds: 5));
      final data = doc.data();
      if (data != null && data.isNotEmpty) {
        final values = data.values.map((v) => v.toString()).toList();
        final selected = values[
            (DateTime.now().millisecondsSinceEpoch + _pickOffset) %
                values.length];
        if (mounted) setState(() => _paragraph = selected);
      }
    } catch (e) {
      if (mounted) setState(() => _paragraph = 'Error loading paragraph');
    }
  }

  void _newParagraph() {
    _pickOffset++;
    _typeController.clear();
    setState(() {
      _comparison = null;
      _typedText = '';
      _paragraph = 'Loading paragraph...';
    });
    _loadParagraph();
  }

  void _check() {
    final text = _typeController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Type the paragraph first, then tap Check'),
        ),
      );
      return;
    }
    final comparison = LetterAnalysis.compare(_paragraph, text);
    _saveSession(comparison);
    setState(() {
      _comparison = comparison;
      _typedText = text;
    });
  }

  Future<void> _saveSession(WordComparisonResult comparison) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await SessionService.instance.saveSession(
        childUid: uid,
        type: 'writing',
        result: comparison,
      );
    } catch (_) {
      // Session history is a bonus for the parent dashboard - don't block
      // the child if saving it fails (e.g. offline).
    }
    try {
      final reward = await GamificationService.instance.recordExercise(
        childUid: uid,
        type: 'writing',
        accuracy: comparison.accuracy,
      );
      if (mounted && reward != null) celebrate(context, reward);
    } catch (_) {
      // Points are a nice extra - never interrupt practice on failures.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Writing Pattern'),
        actions: [
          IconButton(
            onPressed: _newParagraph,
            icon: const Icon(Icons.refresh),
            tooltip: 'New paragraph',
          ),
        ],
      ),
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
                        'Read this, then type it below:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(_paragraph, style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_comparison == null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _typeController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Type the paragraph here...',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _check,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Check my writing'),
                  ),
                ),
              ] else
                _AnalysisCard(
                  comparison: _comparison!,
                  typed: _typedText,
                  target: _paragraph,
                  onRetry: () => setState(() {
                    _comparison = null;
                    _typedText = '';
                    _typeController.clear();
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders the verdict for a writing session in a warm, kid-friendly way:
/// a big emoji headline, the whole sentence color-coded letter by letter
/// (green = right, orange = mixed up, red = missing), the letters the child
/// mixed up, missing letters and one simple exercise tip.
class _AnalysisCard extends StatelessWidget {
  final WordComparisonResult comparison;
  final String typed;
  final String target;
  final VoidCallback onRetry;

  const _AnalysisCard({
    required this.comparison,
    required this.typed,
    required this.target,
    required this.onRetry,
  });

  (String, String, String) _verdict(double accuracy) {
    if (accuracy >= 100) {
      return ('⭐', 'Perfect!', 'Every letter is just right. Superstar!');
    }
    if (accuracy >= 80) {
      return ('🎉', 'Almost perfect!', 'So close - keep going!');
    }
    if (accuracy >= 60) {
      return ('👍', 'Good job!', 'You are getting better every day.');
    }
    return ('💪', 'Keep trying!', 'Practice makes perfect. You can do it!');
  }

  @override
  Widget build(BuildContext context) {
    final confusions = comparison.confusions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final missing = LetterAnalysis.missingLetters(target, typed);
    final alignment = LetterAnalysis.alignWords(target, typed);
    final (emoji, headline, message) = _verdict(comparison.accuracy);
    return Card(
      color: const Color(0xFFFFF8E1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 40)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Score: ${comparison.accuracy.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.brown,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Your sentence:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            _SentencePreview(alignment: alignment),
            const SizedBox(height: 12),
            if (confusions.isNotEmpty) ...[
              const Text(
                'You mixed up these letters:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final entry in confusions)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBE9E7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFF8A80)),
                      ),
                      child: Text(
                        entry.value > 1
                            ? '${LetterAnalysis.labelFor(entry.key)}  ${entry.value}×'
                            : LetterAnalysis.labelFor(entry.key),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Color(0xFFC62828),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '💡  ${LetterAnalysis.exerciseFor(confusions.first.key)}',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ] else ...[
              const Text(
                'No letter mix-ups - every letter is on the right track!',
                style: TextStyle(fontSize: 14, color: Color(0xFF2E7D32)),
              ),
            ],
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Letters to practice:',
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
                        horizontal: 12,
                        vertical: 5,
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
            if (typed.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'You wrote:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(typed, style: const TextStyle(fontSize: 16)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Practice again'),
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

/// Color-codes each letter of the expected sentence: green when the child got
/// it right, orange when it was mixed up, red + underline when it is missing.
class _SentencePreview extends StatelessWidget {
  final List<WordLetterAlignment> alignment;
  const _SentencePreview({required this.alignment});

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    for (final word in alignment) {
      for (var i = 0; i < word.expected.length; i++) {
        final status = word.statuses[i];
        final color = switch (status) {
          LetterStatus.correct => const Color(0xFF2E7D32),
          LetterStatus.wrong => const Color(0xFFEF6C00),
          LetterStatus.missing => const Color(0xFFC62828),
        };
        spans.add(
          TextSpan(
            text: word.expected[i],
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              decoration: status == LetterStatus.missing
                  ? TextDecoration.underline
                  : null,
            ),
          ),
        );
      }
      spans.add(const TextSpan(text: ' '));
    }
    return RichText(
      text: TextSpan(children: spans),
    );
  }
}

/// Simple full-screen camera capture helper, reused by the Flashcard
/// Recognition screen (which imports this file).
class CameraScreen extends StatefulWidget {
  final CameraDescription camera;
  const CameraScreen({super.key, required this.camera});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  late CameraDescription _camera;

  @override
  void initState() {
    super.initState();
    _camera = widget.camera;
    _init();
  }

  Future<void> _init() async {
    _controller = CameraController(
      _camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await _controller!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _capture() async {
    final image = await _controller!.takePicture();
    if (mounted) Navigator.pop(context, image);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Capture')),
      body: _controller == null || !_controller!.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: CameraPreview(_controller!)),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton.icon(
                    onPressed: _capture,
                    icon: const Icon(Icons.camera),
                    label: const Text('Capture'),
                  ),
                ),
              ],
            ),
    );
  }
}