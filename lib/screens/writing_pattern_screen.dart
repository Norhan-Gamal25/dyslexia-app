import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../services/gamification_service.dart';
import '../services/letter_analysis.dart';
import '../services/session_service.dart';
import '../widgets/kid_feedback.dart';

class WritingPatternScreen extends StatefulWidget {
  const WritingPatternScreen({super.key});

  @override
  State<WritingPatternScreen> createState() => _WritingPatternScreenState();
}

class _WritingPatternScreenState extends State<WritingPatternScreen> {
  String _paragraph = 'Loading paragraph...';
  String _result = '';
  bool _processing = false;

  /// The scored comparison of the confirmed scan, rendered as a rich
  /// analysis card (accuracy, confusion chips, missing letters, exercise).
  WordComparisonResult? _comparison;
  String _scannedText = '';

  /// Raw OCR text waiting for the user to confirm/correct it before scoring.
  /// ML Kit's Latin model reads printed text; on a child's handwriting it
  /// often misreads letters, so we let the parent fix the scan before the
  /// letter analysis runs.
  String _scanText = '';
  final TextEditingController _scanController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadParagraph();
  }

  @override
  void dispose() {
    _scanController.dispose();
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
        final selected =
            values[DateTime.now().millisecondsSinceEpoch % values.length];
        if (mounted) setState(() => _paragraph = selected);
      }
    } catch (e) {
      if (mounted) setState(() => _paragraph = 'Error loading paragraph');
    }
  }

  Future<void> _openCamera() async {
    final cameras = await availableCameras();
    if (!mounted) return;
    if (cameras.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No camera available')));
      return;
    }
    setState(() {
      _scanText = '';
      _comparison = null;
      _scannedText = '';
    });
    final image = await Navigator.push<XFile>(
      context,
      MaterialPageRoute(builder: (_) => CameraScreen(camera: cameras.first)),
    );
    if (image != null) {
      _recognize(image);
    }
  }

  Future<void> _recognize(XFile image) async {
    setState(() => _processing = true);
    try {
      final recognizer = TextRecognizer();
      final inputImage = InputImage.fromFilePath(image.path);
      final result = await recognizer.processImage(inputImage);
      recognizer.close();
      final scan = result.text.trim();
      if (mounted) {
        if (scan.isEmpty) {
          setState(() {
            _result =
                'Could not read any text in that photo.\n'
                'Take a closer, well-lit picture and try again.';
            _processing = false;
          });
        } else {
          _scanController.text = scan;
          setState(() {
            _scanText = scan;
            _result = '';
            _processing = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = 'Text recognition failed';
          _processing = false;
        });
      }
    }
  }

  /// Scores the confirmed (and possibly corrected) scan.
  void _confirmScan() {
    final text = _scanController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type what was written, then tap Score')),
      );
      return;
    }
    final comparison = LetterAnalysis.compare(_paragraph, text);
    _saveSession(comparison);
    setState(() {
      _comparison = comparison;
      _scannedText = text;
      _scanText = '';
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
      appBar: AppBar(title: const Text('Writing Pattern')),
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
                        'Write this paragraph:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(_paragraph, style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _processing ? null : _openCamera,
                icon: const Icon(Icons.camera_alt),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Scan Handwriting'),
                ),
              ),
              const SizedBox(height: 16),
              if (_processing)
                const Center(child: CircularProgressIndicator())
              else if (_scanText.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'We read:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _scanController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText:
                                'Fix anything the app misread, then Score',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => setState(() => _scanText = ''),
                                child: const Text('Retake'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: _confirmScan,
                                child: const Text('Score'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              else if (_comparison != null)
                _AnalysisCard(
                  comparison: _comparison!,
                  scanned: _scannedText,
                  target: _paragraph,
                  onRetry: () => setState(() {
                    _comparison = null;
                    _scannedText = '';
                  }),
                )
              else if (_result.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_result),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders the verdict for a handwriting session: accuracy, how many letters
/// were reproduced, which letters the child mixed up (with counts), letters
/// that were missing, a suggested exercise and the corrected scan text.
class _AnalysisCard extends StatelessWidget {
  final WordComparisonResult comparison;
  final String scanned;
  final String target;
  final VoidCallback onRetry;

  const _AnalysisCard({
    required this.comparison,
    required this.scanned,
    required this.target,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final confusions = comparison.confusions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final missing = LetterAnalysis.missingLetters(target, scanned);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Handwriting analysis',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Accuracy: ${comparison.accuracy.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${comparison.correctLetters} of ${comparison.totalLetters} '
              'letter${comparison.totalLetters == 1 ? '' : 's'} correct',
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
            if (scanned.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'You wrote:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(scanned, style: const TextStyle(fontSize: 16)),
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
