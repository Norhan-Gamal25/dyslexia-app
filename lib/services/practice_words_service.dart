import 'package:cloud_firestore/cloud_firestore.dart';

/// Manages the practice words a child has personally built up - on top of
/// the shared word bank in `practicepara/words` - by scanning flashcards or
/// book pages with the camera (see FlashcardScanScreen).
///
/// Firestore shape:
///   users/{uid}/customWords/{wordLowercased}: { word, source, addedAt }
class PracticeWordsService {
  PracticeWordsService._();
  static final instance = PracticeWordsService._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _wordsFor(String uid) =>
      _db.collection('users').doc(uid).collection('customWords');

  /// Adds (or refreshes) a batch of words to the child's personal practice
  /// set. Words are de-duplicated by lowercase spelling, so re-scanning the
  /// same flashcard won't create duplicate entries.
  Future<void> addWords(String uid, List<String> words) async {
    if (words.isEmpty) return;
    final batch = _db.batch();
    final collection = _wordsFor(uid);
    for (final word in words) {
      final trimmed = word.trim();
      if (trimmed.isEmpty) continue;
      final docId = trimmed.toLowerCase();
      batch.set(
        collection.doc(docId),
        {
          'word': trimmed,
          'source': 'flashcard',
          'addedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  /// One-off fetch of the child's custom words, used to mix into the
  /// practice word pool.
  Future<List<String>> getCustomWords(String uid) async {
    final snap = await _wordsFor(uid).get();
    return snap.docs
        .map((d) => (d.data()['word'] ?? '').toString())
        .where((w) => w.isNotEmpty)
        .toList();
  }

  /// Streams the child's custom words, newest first, for any UI that wants
  /// to show what's been added from flashcards.
  Stream<List<String>> watchCustomWords(String uid) {
    return _wordsFor(uid)
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => (d.data()['word'] ?? '').toString())
            .where((w) => w.isNotEmpty)
            .toList());
  }

  Future<void> removeWord(String uid, String word) async {
    await _wordsFor(uid).doc(word.trim().toLowerCase()).delete();
  }
}
