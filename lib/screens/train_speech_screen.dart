import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

class TrainSpeechScreen extends StatefulWidget {
  const TrainSpeechScreen({super.key});

  @override
  State<TrainSpeechScreen> createState() => _TrainSpeechScreenState();
}

class _TrainSpeechScreenState extends State<TrainSpeechScreen> {
  final SpeechToText _speech = SpeechToText();
  String _word = 'Loading...';
  String _highlighted = '';
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _loadWord();
  }

  Future<void> _initSpeech() async {
    await _speech.initialize();
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
        final selected = words[DateTime.now().millisecondsSinceEpoch % words.length];
        if (mounted) {
          setState(() {
            _word = selected;
            _highlighted = '';
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _word = 'No words loaded');
    }
  }

  void _startListening() {
    _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          setState(() => _highlighted = _compare(result.recognizedWords));
        }
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 10),
        localeId: 'en-US',
        partialResults: false,
      ),
    );
    setState(() => _listening = true);
  }

  String _compare(String spoken) {
    if (spoken.isEmpty) return 'Could not hear you. Please try again.';
    final target = _word.toLowerCase();
    final recognized = spoken.toLowerCase();
    final buffer = StringBuffer();
    for (int i = 0; i < recognized.length; i++) {
      final correct = i < target.length && recognized[i] == target[i];
      buffer.write(correct ? '[G]$recognized[i][/G]' : '[R]$recognized[i][/R]');
    }
    return 'Spoken: $recognized\nTarget: $target\n\n'
        '${_matches(recognized, target)} of ${target.length} letters matched.';
  }

  String _matches(String a, String b) {
    int count = 0;
    for (int i = 0; i < a.length && i < b.length; i++) {
      if (a[i] == b[i]) count++;
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Train Speech')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Say this word:',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(_word,
                style: const TextStyle(
                    fontSize: 40, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _listening
                  ? () {
                      _speech.stop();
                      setState(() => _listening = false);
                    }
                  : () {
                      _startListening();
                    },
              icon: Icon(_listening ? Icons.stop : Icons.mic),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(_listening ? 'Stop' : 'Speak'),
              ),
            ),
            const SizedBox(height: 24),
            if (_highlighted.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_highlighted, style: const TextStyle(fontSize: 18)),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadWord,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Another Word'),
            ),
          ],
        ),
      ),
    );
  }
}