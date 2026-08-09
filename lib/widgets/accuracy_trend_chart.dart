import 'package:flutter/material.dart';
import '../services/session_service.dart';

/// A lightweight bar-trend view of accuracy over time, built with plain
/// Flutter widgets (no charting package required).
class AccuracyTrendChart extends StatelessWidget {
  final String title;
  final Color color;
  final List<SessionResult> sessions;

  const AccuracyTrendChart({
    super.key,
    required this.title,
    required this.color,
    required this.sessions,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return _EmptyCard(title: title);
    }
    final average =
        sessions.map((s) => s.accuracy).reduce((a, b) => a + b) /
            sessions.length;
    final latest = sessions.last.accuracy;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                Text(
                  'Avg ${average.toStringAsFixed(0)}% · Latest ${latest.toStringAsFixed(0)}%',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final session in sessions)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _Bar(accuracy: session.accuracy, color: color),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${sessions.length} session${sessions.length == 1 ? '' : 's'} recorded',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double accuracy;
  final Color color;
  const _Bar({required this.accuracy, required this.color});

  @override
  Widget build(BuildContext context) {
    final clamped = accuracy.clamp(0, 100).toDouble();
    final height = 12 + (clamped / 100) * 76;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(clamped.toStringAsFixed(0), style: const TextStyle(fontSize: 10)),
        const SizedBox(height: 2),
        Container(
          width: 20,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String title;
  const _EmptyCard({required this.title});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('No sessions recorded yet.',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
