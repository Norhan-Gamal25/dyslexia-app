import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/session_service.dart';
import '../services/user_service.dart';
import '../services/letter_analysis.dart';
import '../widgets/accuracy_trend_chart.dart';
import '../widgets/confusion_bar_list.dart';
import 'link_child_screen.dart';
import 'login_screen.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  List<String> _childIds = [];
  String? _selectedChild;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ids = await UserService.instance.getChildIds(uid);
    if (!mounted) return;
    setState(() {
      _childIds = ids;
      _selectedChild = ids.isNotEmpty ? ids.first : null;
      _loading = false;
    });
  }

  Future<void> _openLinkScreen() async {
    final linked = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LinkChildScreen()),
    );
    if (linked == true) _loadChildren();
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Link a child',
            onPressed: _openLinkScreen,
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _childIds.isEmpty
              ? _NoChildLinked(onLink: _openLinkScreen)
              : _DashboardBody(
                  childIds: _childIds,
                  selectedChild: _selectedChild!,
                  onChildChanged: (id) => setState(() => _selectedChild = id),
                ),
    );
  }
}

class _NoChildLinked extends StatelessWidget {
  final VoidCallback onLink;
  const _NoChildLinked({required this.onLink});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.family_restroom, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No child account linked yet.\nAsk your child for their link '
              'code to see their progress here.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onLink,
              icon: const Icon(Icons.link),
              label: const Text('Link a child account'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final List<String> childIds;
  final String selectedChild;
  final ValueChanged<String> onChildChanged;

  const _DashboardBody({
    required this.childIds,
    required this.selectedChild,
    required this.onChildChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SessionResult>>(
      stream: SessionService.instance.watchSessions(selectedChild),
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? [];
        final writing = sessions.where((s) => s.type == 'writing').toList();
        final speech = sessions.where((s) => s.type == 'speech').toList();

        final confusions = <String, int>{};
        for (final s in sessions) {
          s.confusions.forEach((key, value) {
            confusions[key] = (confusions[key] ?? 0) + value;
          });
        }
        final topConfusions = confusions.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (childIds.length > 1) ...[
              DropdownButtonFormField<String>(
                value: selectedChild,
                decoration: const InputDecoration(
                  labelText: 'Child',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final id in childIds)
                    DropdownMenuItem(
                      value: id,
                      child: Text('Child ${id.substring(0, 6)}'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onChildChanged(value);
                },
              ),
              const SizedBox(height: 16),
            ],
            if (!snapshot.hasData)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              const Text('Progress overview',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              AccuracyTrendChart(
                title: 'Writing accuracy',
                color: Colors.indigo,
                sessions: writing,
              ),
              const SizedBox(height: 12),
              AccuracyTrendChart(
                title: 'Speech accuracy',
                color: Colors.teal,
                sessions: speech,
              ),
              const SizedBox(height: 24),
              const Text('Recurring letter confusions',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ConfusionBarList(confusions: confusions),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Suggested exercises',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              if (topConfusions.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Once your child completes a few writing or speech '
                      'sessions, personalized exercise suggestions will '
                      'show up here based on the letters they mix up most.',
                    ),
                  ),
                )
              else
                for (final entry in topConfusions.take(3))
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${LetterAnalysis.labelFor(entry.key)} · ${entry.value} time${entry.value == 1 ? '' : 's'}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(LetterAnalysis.exerciseFor(entry.key)),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        );
      },
    );
  }
}
