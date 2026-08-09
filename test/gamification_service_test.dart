import 'package:flutter_test/flutter_test.dart';
import 'package:verbix/services/gamification_service.dart';

void main() {
  group('GamificationService.pointsFor', () {
    test('gives a base amount per activity type plus an accuracy bonus', () {
      expect(GamificationService.instance.pointsFor('writing', 100), 20);
      expect(GamificationService.instance.pointsFor('writing', 80), 18);
      expect(GamificationService.instance.pointsFor('speech', 0), 10);
      expect(GamificationService.instance.pointsFor('practice', 50), 13);
      expect(GamificationService.instance.pointsFor('train', 100), 18);
      expect(GamificationService.instance.pointsFor('story', 0), 15);
      expect(GamificationService.instance.pointsFor('unknown', 0), 5);
    });

    test('clamps runaway accuracy so the bonus never exceeds 10', () {
      expect(GamificationService.instance.pointsFor('writing', 500), 20);
    });
  });

  group('GamificationState', () {
    test('empty state has no points and a default daily goal of 40', () {
      expect(GamificationState.empty.points, 0);
      expect(GamificationState.empty.dailyGoal, 40);
      expect(GamificationState.empty.goalMet, isFalse);
      expect(GamificationState.empty.goalProgress, 0);
    });

    test('goal progress clamps between zero and one', () {
      const state = GamificationState(todayPoints: 80, dailyGoal: 40);
      expect(state.goalProgress, 1.0);
      expect(state.goalMet, isTrue);
    });

    test('goalProgress reduces to zero when todayPoints are missing', () {
      const state = GamificationState(todayPoints: 5, dailyGoal: 40);
      expect(state.goalProgress, closeTo(0.125, 0.001));
      expect(state.goalMet, isFalse);
    });
  });

  group('BadgeCatalog conditions', () {
    GamificationState withSessions(int total, {Map<String, int>? activities}) =>
        GamificationState(
          totalSessions: total,
          activityCounts: activities ?? const {},
          points: total * 8,
          bestAccuracy: 80,
        );

    test('first exercise unlocks First Steps but not the rest', () {
      final one = withSessions(1);
      expect(_earned('first_steps', one), isTrue);
      expect(_earned('builder_5', one), isFalse);
    });

    test('activity counts unlock the writer badge', () {
      final state = withSessions(1, activities: const {'writing': 1});
      expect(_earned('writer', state), isTrue);
      expect(_earned('speechy', state), isFalse);
    });

    test('speaking activities unlock the Little Orator badge', () {
      final speechy = withSessions(1, activities: const {'speech': 1});
      final train = withSessions(1, activities: const {'train': 1});
      expect(_earned('speechy', speechy), isTrue);
      expect(_earned('speechy', train), isTrue);
    });

    test('perfect accuracy unlocks Accuracy Star', () {
      const state = GamificationState(bestAccuracy: 100, totalSessions: 1);
      expect(_earned('accuracy_star', state), isTrue);
      expect(_earned('letter_wizard', state), isTrue);
    });

    test('streaks unlock their badges progressively', () {
      const three = GamificationState(streak: 3, totalSessions: 3);
      const fourteen = GamificationState(streak: 14, totalSessions: 14);
      expect(_earned('streak_3', three), isTrue);
      expect(_earned('streak_7', three), isFalse);
      expect(_earned('streak_14', fourteen), isTrue);
    });
  });
}

bool _earned(String id, GamificationState state) =>
    BadgeCatalog.all.firstWhere((b) => b.id == id).isEarned(state);