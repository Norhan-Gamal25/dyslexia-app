import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../services/practice_words_service.dart';
import 'writing_pattern_screen.dart' show CameraScreen;

/// Lets a child point the camera at a written flashcard or a page of a
/// book, OCRs whatever text is visible, and adds the extracted words to
/// their personal practice set - turning everyday reading material into
/// personalized exercises for Practice Writing.
class FlashcardScanScreen extends StatefulWidget {
  const FlashcardScanScreen({super.key});

  @override
  State<FlashcardScanScreen> createState() => _FlashcardScanScreenState();
}

class _FlashcardScanScreenState extends State<FlashcardScanScreen> {
  bool _processing = false;
  bool _saving = false;
  String? _error;
  List<String> _extractedWords = [];
  final Set<String> _selectedWords = {};

  Future<void> _openCamera() async {
    final cameras = await availableCameras();
    if (!mounted) return;
    if (cameras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No camera available')),
      );
      return;
    }
    final image = await Navigator.push<XFile>(
      context,
      MaterialPageRoute(builder: (_) => CameraScreen(camera: cameras.first)),
    );
    if (image != null) {
      _recognize(image);
    }
  }

  Future<void> _recognize(XFile image) async {
    setState(() {
      _processing = true;
      _error = null;
      _extractedWords = [];
      _selectedWords.clear();
    });
    try {
      final recognizer = TextRecognizer();
      final inputImage = InputImage.fromFilePath(image.path);
      final result = await recognizer.processImage(inputImage);
      recognizer.close();
      final words = _extractWords(result.text);
      if (mounted) {
        setState(() {
          _extractedWords = words;
          _selectedWords.addAll(words);
          _processing = false;
          if (words.isEmpty) {
            _error = 'No readable words found. Try a clearer, closer photo.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _processing = false;
          _error = 'Text recognition failed. Please try again.';
        });
      }
    }
  }

  /// Splits raw OCR text into clean, de-duplicated words suitable for
  /// practice (drops punctuation-only tokens and single letters).
  List<String> _extractWords(String text) {
    final matches = RegExp(r"[A-Za-z']+").allMatches(text);
    final seen = <String>{};
    final words = <String>[];
    for (final match in matches) {
      final raw = match.group(0)!.replaceAll("'", '');
      if (raw.length < 2) continue;
      final key = raw.toLowerCase();
      if (!seen.add(key)) continue;
      words.add(key[0].toUpperCase() + key.substring(1));
    }
    return words;
  }

  Future<void> _addSelectedWords() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _selectedWords.isEmpty) return;
    setState(() => _saving = true);
    try {
      await PracticeWordsService.instance
          .addWords(uid, _selectedWords.toList());
      if (mounted) {
        final count = _selectedWords.length;
        setState(() {
          _extractedWords = [];
          _selectedWords.clear();
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Added $count word(s) to your practice set')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not save words. Check your connection.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flashcard Recognition')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Point the camera at a written flashcard or a page of a book. '
              'We\'ll pull out the words and add them to your practice set.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _processing ? null : _openCamera,
              icon: const Icon(Icons.camera_alt),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Scan Flashcard'),
              ),
            ),
            const SizedBox(height: 16),
            if (_processing) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red)),
              ),
            if (_extractedWords.isNotEmpty) ...[
              const Text('Words found - tap to include or exclude:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _extractedWords.map((word) {
                      final selected = _selectedWords.contains(word);
                      return FilterChip(
                        label: Text(word),
                        selected: selected,
                        onSelected: (value) {
                          setState(() {
                            if (value) {
                              _selectedWords.add(word);
                            } else {
                              _selectedWords.remove(word);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _selectedWords.isEmpty || _saving
                    ? null
                    : _addSelectedWords,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_task),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(_saving
                      ? 'Adding...'
                      : 'Add ${_selectedWords.length} word(s) to Practice Set'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
