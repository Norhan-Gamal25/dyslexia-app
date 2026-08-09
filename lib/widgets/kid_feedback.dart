import 'package:flutter/material.dart';
import '../services/gamification_service.dart';

/// Shows the child applause after an exercise: a point SnackBar for the usual
/// case, or a big shiny dialog when a brand-new badge was unlocked.
void celebrate(BuildContext context, GamificationReward reward) {
  if (reward.newBadges.isNotEmpty) {
    final badge = reward.newBadges.first;
    final remaining = reward.newBadges.length - 1;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          '${badge.emoji}  ${badge.title}!',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(badge.description, textAlign: TextAlign.center),
            if (reward.pointsEarned > 0) ...[
              const SizedBox(height: 8),
              Text(
                '+${reward.pointsEarned} points ⭐',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFFEF6C00)),
              ),
            ],
            if (remaining > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('…and $remaining more badge'
                    '${remaining == 1 ? '' : 's'}!',
                    style: const TextStyle(fontSize: 13)),
              ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Awesome!'),
          ),
        ],
      ),
    );
    return;
  }
  if (reward.pointsEarned > 0) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('+${reward.pointsEarned} points! ⭐ Keep going!'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }
}