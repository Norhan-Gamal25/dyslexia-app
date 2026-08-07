import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class WritingPatternScreen extends StatefulWidget {
  const WritingPatternScreen({super.key});

  @override
  State<WritingPatternScreen> createState() => _WritingPatternScreenState();
}

class _WritingPatternScreenState extends State<WritingPatternScreen> {
  String _paragraph = 'Loading paragraph...';
  String _result = '';
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _loadParagraph();
  }

  Future<void> _loadParagraph() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('practicepara')
          .doc('writingprac')
          .get();
      final data = doc.data();
      if (data != null && data.isNotEmpty) {
        final values = data.values.map((v) => v.toString()).toList();
        final selected = values[DateTime.now().millisecondsSinceEpoch % values.length];
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
    setState(() => _processing = true);
    try {
      final recognizer = TextRecognizer();
      final inputImage = InputImage.fromFilePath(image.path);
      final result = await recognizer.processImage(inputImage);
      recognizer.close();
      if (mounted) {
        setState(() {
          _result = _compare(result.text);
          _processing = false;
        });
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

  String _compare(String scanned) {
    final originalWords = _paragraph.split(RegExp(r'\s+'));
    final scannedWords = scanned.split(RegExp(r'\s+'));
    int correct = 0;
    for (int i = 0; i < originalWords.length && i < scannedWords.length; i++) {
      if (originalWords[i] == scannedWords[i]) correct++;
    }
    final accuracy = originalWords.isEmpty ? 0.0 : (correct / originalWords.length) * 100;
    return 'Accuracy: ${accuracy.toStringAsFixed(1)}%\n'
        'Correct words: $correct/${originalWords.length}\n\n'
        'Scanned text:\n$scanned';
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
                      const Text('Write this paragraph:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
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
    _controller = CameraController(_camera, ResolutionPreset.high,
        enableAudio: false);
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
                Expanded(
                  child: CameraPreview(_controller!),
                ),
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