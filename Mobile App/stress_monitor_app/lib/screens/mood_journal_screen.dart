import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../theme/physiopano_tokens.dart';
import '../services/theme_provider.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

// Mood levels: 1=Very Stressed → 5=Great
const _moods = [
  {'emoji': '😣', 'label': 'Very Stressed', 'mood': 1, 'color': AppColors.levelHigh},
  {'emoji': '😟', 'label': 'Stressed', 'mood': 2, 'color': AppColors.levelHigh},
  {'emoji': '😐', 'label': 'Neutral', 'mood': 3, 'color': AppColors.levelMid},
  {'emoji': '🙂', 'label': 'Good', 'mood': 4, 'color': AppColors.levelLow},
  {'emoji': '😊', 'label': 'Great', 'mood': 5, 'color': AppColors.levelLow},
];

class MoodJournalScreen extends StatefulWidget {
  const MoodJournalScreen({super.key});

  @override
  State<MoodJournalScreen> createState() => _MoodJournalScreenState();
}

class _MoodJournalScreenState extends State<MoodJournalScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = context.read<DatabaseService>();
    final auth = context.read<AuthService>();
    final entries = await db.getMoodEntries(auth.userId);
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Mood Journal')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _entries.length,
                  itemBuilder: (ctx, i) => _MoodTile(entry: _entries[i]),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await showMoodCheckIn(context);
          if (added == true) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text("Log Mood"),
        backgroundColor: AppColors.emerald,
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Reveal(
        child: SceneCard(
          mood: PanoMood.thinking,
          blobColor: PpAccent.sun,
          title: 'How does today feel?',
          message: 'Log a mood with the button below. A word or two is plenty.',
        ),
      ),
    );
  }
}

class _MoodTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _MoodTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final mood = (entry['mood'] as int?) ?? 3;
    final moodData = _moods[(mood.clamp(1, _moods.length)) - 1];
    final color = moodData['color'] as Color;
    final ts = DateTime.fromMillisecondsSinceEpoch(entry['timestamp'] as int);
    final note = entry['note'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  moodData['emoji'] as String,
                  style: const TextStyle(fontSize: 26),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    moodData['label'] as String,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  Text(
                    DateFormat('MMM d, yyyy  h:mm a').format(ts),
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  if (note != null && note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        note,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the mood check-in bottom sheet.
/// Returns true if an entry was saved, false/null otherwise.
Future<bool?> showMoodCheckIn(BuildContext context, {bool isDailyPrompt = false}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (ctx) => _MoodCheckInSheet(isDailyPrompt: isDailyPrompt),
  );
}

class _MoodCheckInSheet extends StatefulWidget {
  final bool isDailyPrompt;
  const _MoodCheckInSheet({this.isDailyPrompt = false});

  @override
  State<_MoodCheckInSheet> createState() => _MoodCheckInSheetState();
}

class _MoodCheckInSheetState extends State<_MoodCheckInSheet> {
  int? _selectedMood;
  final _noteController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.isDailyPrompt ? 'How are you feeling today?' : 'Log Your Mood',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap an emoji to select your current mood',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _moods.map((m) {
              final moodVal = m['mood'] as int;
              final isSelected = _selectedMood == moodVal;
              final color = m['color'] as Color;
              return GestureDetector(
                onTap: () => setState(() => _selectedMood = moodVal),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: isSelected
                        ? Border.all(color: color, width: 2)
                        : Border.all(color: Colors.transparent, width: 2),
                  ),
                  child: Column(
                    children: [
                      Text(m['emoji'] as String,
                          style: const TextStyle(fontSize: 32)),
                      const SizedBox(height: 4),
                      Text(
                        (m['label'] as String).split(' ').first,
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected ? color : AppColors.textMuted,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            decoration: InputDecoration(
              hintText: 'Add a note (optional)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            maxLines: 2,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.isDailyPrompt)
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Skip'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _selectedMood == null || _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  minimumSize: const Size(120, 44),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_selectedMood == null) return;
    setState(() => _saving = true);

    final db = context.read<DatabaseService>();
    final auth = context.read<AuthService>();
    final moodData = _moods[_selectedMood! - 1];
    final today = DateTime.now();
    final dateKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    await db.saveMoodEntry(
      userId: auth.userId,
      date: dateKey,
      mood: _selectedMood!,
      emoji: moodData['emoji'] as String,
      label: moodData['label'] as String,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );

    if (mounted) Navigator.pop(context, true);
  }
}
