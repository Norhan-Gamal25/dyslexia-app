import 'package:cloud_firestore/cloud_firestore.dart';
import 'letter_analysis.dart';

/// One completed writing or speech practice attempt, as read back from
/// Firestore for the dashboard.
class SessionResult {
  final String type; // 'writing' or 'speech'
  final double accuracy;
  final int correctWords;
  final int totalWords;
  final Map<String, int> confusions;
  final DateTime? timestamp;

  SessionResult({
    required this.type,
    required this.accuracy,
    required this.correctWords,
    required this.totalWords,
    required this.confusions,
    required this.timestamp,
  });

  factory SessionResult.fromMap(Map<String, dynamic> map) {
    final rawConfusions = map['confusions'];
    final confusions = <String, int>{};
    if (rawConfusions is Map) {
      rawConfusions.forEach((key, value) {
        if (value is num) confusions[key.toString()] = value.toInt();
      });
    }
    final ts = map['timestamp'];
    return SessionResult(
      type: map['type']?.toString() ?? 'writing',
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0.0,
      correctWords: (map['correctWords'] as num?)?.toInt() ?? 0,
      totalWords: (map['totalWords'] as num?)?.toInt() ?? 0,
      confusions: confusions,
      timestamp: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class SessionService {
  SessionService._();
  static final instance = SessionService._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _sessionsFor(String childUid) =>
      _db.collection('users').doc(childUid).collection('sessions');

  Future<void> saveSession({
    required String childUid,
    required String type,
    required WordComparisonResult result,
  }) async {
    await _sessionsFor(childUid).add({
      'type': type,
      'accuracy': result.accuracy,
      'correctWords': result.correctWords,
      'totalWords': result.totalWords,
      'confusions': result.confusions,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Streams a child's sessions oldest-first, ready for plotting a trend.
  Stream<List<SessionResult>> watchSessions(String childUid) {
    return _sessionsFor(childUid)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => SessionResult.fromMap(d.data())).toList());
  }
}
