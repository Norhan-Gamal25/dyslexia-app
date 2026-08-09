import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import 'login_screen.dart';
import 'writing_pattern_screen.dart';
import 'speech_pattern_screen.dart';
import 'practice_writing_screen.dart';
import 'train_speech_screen.dart';
import 'parent_dashboard_screen.dart';

/// Routes the signed-in user to the right home: the Parent Dashboard for
/// parent accounts, or the practice menu for child accounts.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Future<UserRole> _roleFuture = _loadRole();

  Future<UserRole> _loadRole() async {
    // Covers accounts created before roles existed - defaults them to child.
    await UserService.instance.ensureUserDoc();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return UserRole.child;
    return UserService.instance.getRole(uid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserRole>(
      future: _roleFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == UserRole.parent) {
          return const ParentDashboardScreen();
        }
        return const _ChildHome();
      },
    );
  }
}

class _ChildHome extends StatelessWidget {
  const _ChildHome();

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _showLinkCode(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final data = await UserService.instance.getUserData(uid);
    final code = data?['linkCode']?.toString() ?? 'Not available';
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('My Link Code'),
        content: Text(
          'Share this code with a parent so they can see your progress:\n\n$code',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _MenuItem('Screening', Icons.fact_check, Colors.purple),
      _MenuItem('Writing Pattern', Icons.edit_note, Colors.indigo),
      _MenuItem('Speech Pattern', Icons.mic, Colors.teal),
      _MenuItem('Practice Writing', Icons.draw, Colors.deepOrange),
      _MenuItem('Train Speech', Icons.record_voice_over, Colors.pink),
      _MenuItem('My Link Code', Icons.qr_code, Colors.green),
      _MenuItem('Log out', Icons.logout, Colors.blueGrey),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verbix'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        children: [
          for (final item in items) _buildCard(context, item),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, _MenuItem item) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: InkWell(
        onTap: () => _onTap(context, item.title),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: 48, color: item.color),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                item.title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onTap(BuildContext context, String title) {
    switch (title) {
      case 'Screening':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Coming Soon')),
        );
        break;
      case 'Writing Pattern':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const WritingPatternScreen()));
        break;
      case 'Speech Pattern':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SpeechPatternScreen()));
        break;
      case 'Practice Writing':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PracticeWritingScreen()));
        break;
      case 'Train Speech':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TrainSpeechScreen()));
        break;
      case 'My Link Code':
        _showLinkCode(context);
        break;
      case 'Log out':
        _logout(context);
        break;
    }
  }
}

class _MenuItem {
  final String title;
  final IconData icon;
  final Color color;
  _MenuItem(this.title, this.icon, this.color);
}
