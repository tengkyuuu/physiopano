import 'package:flutter/material.dart';
import '../theme/physiopano_tokens.dart';
import '../services/theme_provider.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/session.dart';
import 'session_detail_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedMonth =
      DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, double> _dailyStress = {};
  Map<String, List<Session>> _dailySessions = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db = context.read<DatabaseService>();
    final userId = context.read<AuthService>().userId;
    final dailyStress = await db.getDailyStressStats(userId);
    final sessions = await db.loadSessions(userId);

    final dailySessions = <String, List<Session>>{};
    for (final s in sessions) {
      final key = _dateKey(s.startTime);
      dailySessions.putIfAbsent(key, () => []).add(s);
    }

    if (mounted) {
      setState(() {
        _dailyStress = dailyStress;
        _dailySessions = dailySessions;
        _loading = false;
      });
    }
  }

  String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Stress Calendar'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildLegend(),
                _buildMonthHeader(),
                _buildDayLabels(),
                Expanded(child: _buildCalendarGrid()),
              ],
            ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _LegendDot(color: Colors.grey.shade300, label: 'No data'),
          const SizedBox(width: 16),
          const _LegendDot(color: AppColors.levelLow, label: 'Within usual'),
          const SizedBox(width: 16),
          const _LegendDot(color: AppColors.levelMid, label: 'A little different'),
          const SizedBox(width: 16),
          const _LegendDot(color: AppColors.levelHigh, label: 'Different'),
        ],
      ),
    );
  }

  Widget _buildMonthHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() {
              _focusedMonth = DateTime(
                  _focusedMonth.year, _focusedMonth.month - 1);
            }),
          ),
          Text(
            DateFormat('MMMM yyyy').format(_focusedMonth),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() {
              _focusedMonth = DateTime(
                  _focusedMonth.year, _focusedMonth.month + 1);
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildDayLabels() {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: days
            .map((d) => Expanded(
                  child: Center(
                    child: Text(d,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        )),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7; // 0=Sun…6=Sat

    final totalCells = startWeekday + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: rows * 7,
      itemBuilder: (context, index) {
        final dayNumber = index - startWeekday + 1;
        if (dayNumber < 1 || dayNumber > daysInMonth) {
          return const SizedBox();
        }

        final date = DateTime(_focusedMonth.year, _focusedMonth.month, dayNumber);
        final key = _dateKey(date);
        final stress = _dailyStress[key];
        final sessions = _dailySessions[key] ?? [];
        final isToday = key == _dateKey(DateTime.now());

        return GestureDetector(
          onTap: sessions.isEmpty ? null : () => _showDaySessions(date, sessions),
          child: Container(
            decoration: BoxDecoration(
              color: _stressColor(stress),
              borderRadius: BorderRadius.circular(16),
              border: isToday
                  ? Border.all(color: AppColors.emerald, width: 2)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$dayNumber',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isToday ? FontWeight.bold : FontWeight.normal,
                    color: stress != null
                        ? _stressTextColor(stress)
                        : AppColors.textSecondary,
                  ),
                ),
                if (sessions.isNotEmpty)
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: stress != null
                          ? _stressTextColor(stress).withValues(alpha: 0.7)
                          : AppColors.textSecondary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _stressColor(double? avg) {
    if (avg == null || avg < 0) return Colors.grey.shade200;
    if (avg < 33) return AppColors.levelLow.withValues(alpha: 0.7);
    if (avg < 66) return AppColors.levelMid.withValues(alpha: 0.7);
    return AppColors.levelHigh.withValues(alpha: 0.7);
  }

  Color _stressTextColor(double avg) {
    if (avg < 33) return PpAccent.mint;
    if (avg < 66) return Colors.yellow.shade900;
    return Colors.red.shade900;
  }

  void _showDaySessions(DateTime date, List<Session> sessions) {
    final fmt = DateFormat('MMMM d, yyyy');
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fmt.format(date),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${sessions.length} session${sessions.length != 1 ? 's' : ''}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            ...sessions.map((s) {
              final avg = s.avgStressIndex;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: _stressColor(avg >= 0 ? avg : null),
                  child: Text(
                    avg >= 0 ? avg.toStringAsFixed(0) : '--',
                    style: TextStyle(
                      fontSize: 11,
                      color: avg >= 0
                          ? _stressTextColor(avg)
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(DateFormat('h:mm a').format(s.startTime)),
                subtitle: Text(s.durationString),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SessionDetailScreen(session: s),
                    ),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}
