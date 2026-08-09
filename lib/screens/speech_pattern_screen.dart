import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/letter_analysis.dart';
import '../services/session_service.dart';

class SpeechPatternScreen extends StatefulWidget {
  const SpeechPatternScreen({super.key});

  @override
  State<SpeechPatternScreen> createState() => _SpeechPatternScreenState();
}

class _SpeechPatternScreenState extends State<SpeechPatternScreen> {
  final SpeechToText _speech = SpeechToText();
  String _paragraph = 'Loading paragraph...';
  String _result = '';
  String _status = 'Press button and start speaking';
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _loadParagraph();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    await _speech.initialize();
  }

  Future<void> _loadParagraph() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('practicepara')
          .doc('speechpat')
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

  void _startListening() {
    _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          final comparison =
              LetterAnalysis.compare(_paragraph, result.recognizedWords);
          _saveSession(comparison);
          if (mounted) {
            setState(
                () => _result = _formatResult(comparison, result.recognizedWords));
          }
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 20),
        localeId: 'en-US',
        partialResults: false,
      ),
    );
    setState(() {
      _listening = true;
      _status = 'Listening...';
    });
  }

  void _stopListening() {
    _speech.stop();
    setState(() {
      _listening = false;
      _status = 'Press button and start speaking';
    });
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
  }

  String _formatResult(WordComparisonResult comparison, String spoken) {
    final buffer = StringBuffer()
      ..writeln('Accuracy: ${comparison.accuracy.toStringAsFixed(1)}%')
      ..writeln(
          'Correct words: ${comparison.correctWords}/${comparison.totalWords}');
    if (comparison.confusions.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Letters to watch: '
          '${comparison.confusions.keys.map(LetterAnalysis.labelFor).join(', ')}');
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
                      const Text('Read this paragraph aloud:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
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
                onPressed: _listening ? _stopListening : _startListening,
                icon: Icon(_listening ? Icons.stop : Icons.mic),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(_listening ? 'Stop Listening' : 'Start Speaking'),
                ),
              ),
              const SizedBox(height: 16),
              if (_result.isNotEmpty)
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