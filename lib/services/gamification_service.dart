import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Point in time gamification stats for a child, persisted to
/// `users/{uid}/profile/gamification`.
@immutable
class GamificationState {
  final int points;
  final int todayPoints;
  final int dailyGoal;
  final int streak;
  final int longestStreak;
  final int totalSessions;
  final int bestAccuracy; // 0-100
  final Map<String, int> activityCounts; // type -> how many times done
  final Set<String> badges;
  final String lastActivityDate; // yyyy-MM-dd

  const GamificationState({
    this.points = 0,
    this.todayPoints = 0,
    this.dailyGoal = 40,
    this.streak = 0,
    this.longestStreak = 0,
    this.totalSessions = 0,
    this.bestAccuracy = 0,
    this.activityCounts = const {},
    this.badges = const {},
    this.lastActivityDate = '',
  });

  static const GamificationState empty = GamificationState();

  factory GamificationState.fromMap(Map<String, dynamic> map) {
    final activities = <String, int>{};
    final rawActivities = map['activityCounts'];
    if (rawActivities is Map) {
      rawActivities.forEach((k, v) {
        if (v is num) activities[k.toString()] = v.toInt();
      });
    }
    final badgesRaw = map['badges'];
    final badges = <String>{};
    if (badgesRaw is List) {
      badges.addAll(badgesRaw.map((e) => e.toString()));
    } else if (badgesRaw is Map) {
      badges.addAll(badgesRaw.keys.map((e) => e.toString()));
    }
    return GamificationState(
      points: (map['points'] as num?)?.toInt() ?? 0,
      todayPoints: (map['todayPoints'] as num?)?.toInt() ?? 0,
      dailyGoal: (map['dailyGoal'] as num?)?.toInt() ?? 40,
      streak: (map['streak'] as num?)?.toInt() ?? 0,
      longestStreak: (map['longestStreak'] as num?)?.toInt() ?? 0,
      totalSessions: (map['totalSessions'] as num?)?.toInt() ?? 0,
      bestAccuracy: (map['bestAccuracy'] as num?)?.toInt() ?? 0,
      activityCounts: activities,
      badges: badges,
      lastActivityDate: map['lastActivityDate']?.toString() ?? '',
    );
  }

  double get goalProgress =>
      dailyGoal <= 0 ? 0 : (todayPoints / dailyGoal).clamp(0.0, 1.0);

  bool get goalMet => todayPoints >= dailyGoal && dailyGoal > 0;
}

/// A single unlockable achievement shown in the Rewards screen.
class BadgeDefinition {
  final String id;
  final String title;
  final String description;
  final String emoji;
  final bool Function(GamificationState) isEarned;

  const BadgeDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    required this.isEarned,
  });
}

/// The full list of badges a child can unlock. Conditions run against the
/// live [GamificationState] so they are easy to reason about and test.
class BadgeCatalog {
  static final List<BadgeDefinition> all = [
    BadgeDefinition(
      id: 'first_steps',
      title: 'First Steps',
      description: 'Complete your very first exercise.',
      emoji: '🐾',
      isEarned: (s) => s.totalSessions >= 1,
    ),
    BadgeDefinition(
      id: 'accuracy_star',
      title: 'Accuracy Star',
      description: 'Score 100% on any exercise.',
      emoji: '⭐',
      isEarned: (s) => s.bestAccuracy >= 100,
    ),
    BadgeDefinition(
      id: 'letter_master',
      title: 'Letter Master',
      description: 'Score 80% or better on any exercise.',
      emoji: '🏅',
      isEarned: (s) => s.bestAccuracy >= 80,
    ),
    BadgeDefinition(
      id: 'writer',
      title: 'Young Writer',
      description: 'Finish a writing exercise.',
      emoji: '✍️',
      isEarned: (s) => (s.activityCounts['writing'] ?? 0) > 0,
    ),
    BadgeDefinition(
      id: 'speechy',
      title: 'Little Orator',
      description: 'Finish a speaking exercise.',
      emoji: '🎤',
      isEarned: (s) => (s.activityCounts['speech'] ?? 0) > 0 ||
          (s.activityCounts['train'] ?? 0) > 0,
    ),
    BadgeDefinition(
      id: 'storyteller',
      title: 'Story Reader',
      description: 'Read a whole story from start to finish.',
      emoji: '📖',
      isEarned: (s) => (s.activityCounts['story'] ?? 0) > 0,
    ),
    BadgeDefinition(
      id: 'builder_5',
      title: 'Busy Learner',
      description: 'Complete 5 exercises in total.',
      emoji: '🧱',
      isEarned: (s) => s.totalSessions >= 5,
    ),
    BadgeDefinition(
      id: 'builder_10',
      title: 'Super Explorer',
      description: 'Complete 10 exercises in total.',
      emoji: '🗺️',
      isEarned: (s) => s.totalSessions >= 10,
    ),
    BadgeDefinition(
      id: 'builder_25',
      title: 'Reading Champion',
      description: 'Complete 25 exercises in total.',
      emoji: '🏆',
      isEarned: (s) => s.totalSessions >= 25,
    ),
    BadgeDefinition(
      id: 'goal_first',
      title: 'Goal Getter',
      description: 'Reach your daily goal in one day.',
      emoji: '🎯',
      isEarned: (s) => s.goalMet,
    ),
    BadgeDefinition(
      id: 'streak_3',
      title: 'On a Roll',
      description: 'Practice 3 days in a row.',
      emoji: '🔥',
      isEarned: (s) => s.streak >= 3,
    ),
    BadgeDefinition(
      id: 'streak_7',
      title: 'Weekly Hero',
      description: 'Practice 7 days in a row.',
      emoji: '🦸',
      isEarned: (s) => s.streak >= 7,
    ),
    BadgeDefinition(
      id: 'streak_14',
      title: 'Unstoppable',
      description: 'Practice 14 days in a row.',
      emoji: '🚀',
      isEarned: (s) => s.streak >= 14,
    ),
    BadgeDefinition(
      id: 'points_200',
      title: 'Point Collector',
      description: 'Collect 200 points in total.',
      emoji: '💰',
      isEarned: (s) => s.points >= 200,
    ),
    BadgeDefinition(
      id: 'points_500',
      title: 'Star Collector',
      description: 'Collect 500 points in total.',
      emoji: '🌟',
      isEarned: (s) => s.points >= 500,
    ),
  ];
}

/// What a single completed exercise handed back to the UI.
class GamificationReward {
  final int pointsEarned;
  final List<BadgeDefinition> newBadges;
  final GamificationState state;

  const GamificationReward({
    required this.pointsEarned,
    required this.newBadges,
    required this.state,
  });
}

/// Tracks points, streaks, daily goals and badges for a child.
///
/// State lives in `users/{uid}/profile/gamification` so the parent dashboard
/// (and the Rewards screen) can react to it live, and so a child's hard-won
/// progress survives reinstalls and moves between devices.
///
/// Rewards are *resilient*: every exercise is also mirrored to an in-memory
/// cache and SharedPreferences. If Firestore is unreachable or the published
/// rules don't yet allow the `profile` subcollection (the repo's rules file
/// does, but the deployed copy might not), points and badges still accrue
/// locally and the Rewards screen still updates - nothing grinds to a halt.
class GamificationService {
  GamificationService._();
  static final instance = GamificationService._();

  // Lazy: the service is a singleton and pure helpers like [pointsFor] are
  // unit-tested without a Firebase app initialised, so only resolve the
  // Firestore instance when it is actually needed.
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // In-memory source of truth used when Firestore is unavailable, plus the
  // per-user broadcast controllers that power the Rewards screen live updates.
  final Map<String, GamificationState> _state = {};
  final Map<String, StreamController<GamificationState>> _watchers = {};

  DocumentReference<Map<String, dynamic>> _doc(String childUid) => _db
      .collection('users')
      .doc(childUid)
      .collection('profile')
      .doc('gamification');

  static const _prefsKey = 'verbix_gamification_v1_';

  /// Live stream of the child's stats. Falls back to the local cache when the
  /// Firestore listener errors (offline, or rules not yet published).
  Stream<GamificationState> watch(String childUid) {
    final existing = _watchers[childUid];
    if (existing != null) {
      final cached = _state[childUid];
      if (cached != null) existing.add(cached);
      return existing.stream;
    }

    final controller = StreamController<GamificationState>.broadcast();
    _watchers[childUid] = controller;
    // Seed immediately from memory so the UI never shows an empty wall.
    final cached = _state[childUid];
    if (cached != null) conditionalAdd(controller, cached);
    // Then hydrate from disk so progress survives restarts.
    unawaited(_hydrate(childUid, controller));
    _subscribeRemote(childUid, controller);
    return controller.stream;
  }

  void _subscribeRemote(
    String uid,
    StreamController<GamificationState> controller,
  ) {
    _doc(uid).snapshots().listen(
      (snap) {
        final remote = snap.exists
            ? GamificationState.fromMap(snap.data() ?? const {})
            : GamificationState.empty;
        _state[uid] = remote;
        conditionalAdd(controller, remote);
      },
      onError: (Object e, StackTrace st) {
        final local = _state[uid] ?? GamificationState.empty;
        _state[uid] = local;
        conditionalAdd(controller, local);
      },
    );
  }

  static void conditionalAdd(
    StreamController<GamificationState> controller,
    GamificationState state,
  ) {
    if (!controller.isClosed) controller.add(state);
  }

  /// Loads the child's current stats: Firestore first, then the local cache.
  Future<GamificationState> load(String childUid) async {
    final inMemory = _state[childUid];
    if (inMemory != null) return inMemory;
    try {
      final snap =
          await _doc(childUid).get().timeout(const Duration(seconds: 5));
      if (snap.exists) {
        final state = GamificationState.fromMap(snap.data() ?? const {});
        _state[childUid] = state;
        return state;
      }
    } catch (_) {
      // Firestore blocked/unavailable - fall through to the local cache.
    }
    final cached = await _readLocal(childUid);
    if (cached != null) {
      _state[childUid] = cached;
      return cached;
    }
    return GamificationState.empty;
  }

  Future<void> _hydrate(
    String uid,
    StreamController<GamificationState> controller,
  ) async {
    if (_state.containsKey(uid)) return;
    final cached = await _readLocal(uid);
    if (cached != null) {
      _state[uid] = cached;
      conditionalAdd(controller, cached);
    }
  }

  Future<void> _persistLocal(String uid, GamificationState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey + uid, jsonEncode(state.toMap()));
    } catch (_) {
      // Best-effort cache; never break the exercise on a prefs failure.
    }
  }

  Future<GamificationState?> _readLocal(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey + uid);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return GamificationState.fromMap(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// Number of points a completed exercise is worth: a base amount for the
  /// activity type plus an accuracy bonus (up to 10) so effort and precision
  /// both matter.
  int pointsFor(String type, double accuracy) {
    int base;
    switch (type) {
      case 'writing':
        base = 10;
        break;
      case 'practice':
        base = 8;
        break;
      case 'speech':
        base = 10;
        break;
      case 'train':
        base = 8;
        break;
      case 'story':
        base = 15;
        break;
      default:
        base = 5;
    }
    final bonus = accuracy.clamp(0.0, 100.0).floor() ~/ 10;
    return base + bonus;
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Records one finished exercise: updates points, the daily goal progress,
  /// the streak and any newly unlocked badges.
  ///
  /// The result is always applied to the local cache (and persisted to
  /// SharedPreferences) so rewards work even without Firestore, and mirrored
  /// to Firestore via a merge so a simultaneous write on another device can
  /// not clobber progress. Returns the points earned + newly unlocked badges,
  /// or null only when even the local computation itself failed.
  Future<GamificationReward?> recordExercise({
    required String childUid,
    required String type,
    required double accuracy,
    DateTime? now,
  }) async {
    try {
      final current = await load(childUid);
      final today = now ?? DateTime.now();
      final todayKey = _dayKey(today);
      final yesterday = _dayKey(today.subtract(const Duration(days: 1)));

      final pointsEarned = pointsFor(type, accuracy);
      final isNewDay = current.lastActivityDate != todayKey;
      final newStreak = isNewDay
          ? (current.lastActivityDate == yesterday ? current.streak + 1 : 1)
          : current.streak;

      final candidate = GamificationState(
        points: current.points + pointsEarned,
        todayPoints: isNewDay ? pointsEarned : current.todayPoints + pointsEarned,
        dailyGoal: current.dailyGoal,
        streak: newStreak,
        longestStreak: max(current.longestStreak, newStreak),
        totalSessions: current.totalSessions + 1,
        bestAccuracy: max(current.bestAccuracy, accuracy.round()),
        activityCounts:
            {...current.activityCounts, type: (current.activityCounts[type] ?? 0) + 1},
        badges: current.badges,
        lastActivityDate: todayKey,
      );

      final newBadges = BadgeCatalog.all
          .where((b) => !current.badges.contains(b.id) && b.isEarned(candidate))
          .toList();
      final allBadges = {...candidate.badges, ...newBadges.map((b) => b.id)};
      final finalState = GamificationState(
        points: candidate.points,
        todayPoints: candidate.todayPoints,
        dailyGoal: candidate.dailyGoal,
        streak: candidate.streak,
        longestStreak: candidate.longestStreak,
        totalSessions: candidate.totalSessions,
        bestAccuracy: candidate.bestAccuracy,
        activityCounts: candidate.activityCounts,
        badges: allBadges,
        lastActivityDate: candidate.lastActivityDate,
      );

      // Always reflect the new totals locally first so the UI reacts, then
      // mirror to Firestore best-effort.
      _state[childUid] = finalState;
      final controller = _watchers[childUid];
      if (controller != null) conditionalAdd(controller, finalState);
      unawaited(_persistLocal(childUid, finalState));
      try {
        await _doc(childUid).set(finalState.toMap(), SetOptions(merge: true));
      } catch (_) {
        // Firestore blocked (e.g. rules not yet published). Local rewards
        // still count; sync resumes once Firestore is reachable/writable.
      }

      return GamificationReward(
        pointsEarned: pointsEarned,
        newBadges: newBadges,
        state: finalState,
      );
    } catch (_) {
      return null;
    }
  }
}

extension GamificationStateMap on GamificationState {
  Map<String, dynamic> toMap() => {
        'points': points,
        'todayPoints': todayPoints,
        'dailyGoal': dailyGoal,
        'streak': streak,
        'longestStreak': longestStreak,
        'totalSessions': totalSessions,
        'bestAccuracy': bestAccuracy,
        'activityCounts': activityCounts,
        'badges': badges.toList(),
        'lastActivityDate': lastActivityDate,
      };
}