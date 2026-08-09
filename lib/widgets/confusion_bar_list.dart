import 'package:flutter/material.dart';
import '../services/letter_analysis.dart';

/// Shows aggregated letter-confusion counts as horizontal bars, most
/// frequent first.
class ConfusionBarList extends StatelessWidget {
  final Map<String, int> confusions;

  const ConfusionBarList({super.key, required this.confusions});

  @override
  Widget build(BuildContext context) {
    if (confusions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No recurring letter mixups detected yet — keep practicing!',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    final entries = confusions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxCount = entries.first.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    LetterAnalysis.labelFor(entry.key),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: entry.value / maxCount,
                      minHeight: 14,
                      backgroundColor: Colors.grey.shade200,
                      valueColor:
                          const AlwaysStoppedAnimation(Colors.deepOrange),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${entry.value}'),
              ],
            ),
          ),
      ],
    );
  }
}
