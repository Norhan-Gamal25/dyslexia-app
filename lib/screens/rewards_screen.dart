import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/gamification_service.dart';

/// Rewards screen for the child: shows total points, the practice streak,
/// today's progress toward the daily goal, and the full badge wall - locked
/// badges stay visible as goals, earned ones light up.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('My Rewards')),
      body: uid == null
          ? const Center(child: Text('Please sign in to see your rewards.'))
          : StreamBuilder<GamificationState>(
              stream: GamificationService.instance.watch(uid),
              builder: (context, snapshot) {
                final state =
                    snapshot.data ?? GamificationState.empty;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _StatsHeader(state: state),
                    const SizedBox(height: 20),
                    _BadgeGrid(state: state),
                  ],
                );
              },
            ),
    );
  }
}

/// Big playful summary: total points, streak flame and today's goal ring.
class _StatsHeader extends StatelessWidget {
  final GamificationState state;
  const _StatsHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            emoji: '⭐',
            value: '${state.points}',
            label: 'Total points',
            color: Colors.amber,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            emoji: '🔥',
            value: '${state.streak}',
            label: 'Day streak',
            color: Colors.deepOrange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _DailyGoalCard(state: state),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final MaterialColor color;

  const _StatCard({
    required this.emoji,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.shade200, width: 2),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color.shade800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: color.shade700),
          ),
        ],
      ),
    );
  }
}

/// Today's goal as a circular ring with a "Goal met!" celebration.
class _DailyGoalCard extends StatelessWidget {
  final GamificationState state;
  const _DailyGoalCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final progress = state.goalProgress;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.shade200, width: 2),
      ),
      child: state.goalMet
          ? Column(
              children: [
                const Text('🎯', style: TextStyle(fontSize: 26)),
                const SizedBox(height: 6),
                const Text(
                  'Goal met!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${state.todayPoints} pts today',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            )
          : Column(
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 6,
                        backgroundColor: Colors.green.shade100,
                        color: Colors.green,
                      ),
                      Center(
                        child: Text(
                          '${state.todayPoints}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'To ${state.dailyGoal} pts today',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
    );
  }
}

/// The wall of all badges: earned ones glow, locked ones stay grey.
class _BadgeGrid extends StatelessWidget {
  final GamificationState state;
  const _BadgeGrid({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Badges',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
          children: [
            for (final badge in BadgeCatalog.all) _BadgeTile(badge: badge, state: state),
          ],
        ),
      ],
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final BadgeDefinition badge;
  final GamificationState state;
  const _BadgeTile({required this.badge, required this.state});

  @override
  Widget build(BuildContext context) {
    final earned = state.badges.contains(badge.id);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _showBadgeDialog(context),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: earned ? Colors.amber.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: earned ? Colors.amber.shade300 : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              earned ? badge.emoji : '🔒',
              style: const TextStyle(fontSize: 30),
            ),
            const SizedBox(height: 6),
            Text(
              badge.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: earned ? Colors.black87 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              earned ? 'Earned' : 'Keep going',
              style: TextStyle(
                fontSize: 10,
                color: earned ? Colors.green.shade700 : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBadgeDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${badge.emoji}  ${badge.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              badge.title,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Text(
              badge.description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}