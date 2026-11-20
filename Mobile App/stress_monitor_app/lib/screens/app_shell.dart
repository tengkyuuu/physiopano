import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/physiopano_tokens.dart';
import 'breathing_screen.dart';
import 'dashboard_screen.dart';
import 'notification_screen.dart';
import 'session_history_screen.dart';
import 'settings_screen.dart';

/// The visible tab (0 Today, 1 History, 2 Alerts, 3 Profile). Tabs are kept
/// alive in a Stack, so screens that must refresh or act when they are
/// actually opened (e.g. Alerts marking items read) listen to this.
final ValueNotifier<int> currentAppTab = ValueNotifier<int>(0);

/// Shell with the floating Paper navigation pill.
///
/// The active tab sits in a soft inset pill that slides between slots (shared
/// layout transition); tabs cross-fade; the centre Breathe tile springs.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    currentAppTab.value = 0; // a new shell (e.g. after sign-in) starts on Today
  }

  static const _pages = <Widget>[
    DashboardScreen(),
    SessionHistoryScreen(),
    NotificationScreen(),
    SettingsScreen(),
  ];

  static const _items = [
    (Icons.monitor_heart_outlined, Icons.monitor_heart, 'Today'),
    (Icons.insights_outlined, Icons.insights, 'History'),
    (Icons.notifications_none_rounded, Icons.notifications_rounded, 'Alerts'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          for (var i = 0; i < _pages.length; i++)
            IgnorePointer(
              ignoring: i != _currentIndex,
              child: AnimatedOpacity(
                opacity: i == _currentIndex ? 1 : 0,
                duration: PpMotion.base,
                curve: PpMotion.ease,
                child: AnimatedSlide(
                  offset: i == _currentIndex ? Offset.zero : const Offset(0, 0.015),
                  duration: PpMotion.slow,
                  curve: PpMotion.ease,
                  child: TickerMode(enabled: i == _currentIndex, child: _pages[i]),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset > 0 ? bottomInset : 14),
        child: _PaperNav(
          index: _currentIndex,
          items: _items,
          onSelect: (i) {
            setState(() => _currentIndex = i);
            currentAppTab.value = i;
          },
          onBreathe: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BreathingScreen())),
        ),
      ),
    );
  }
}

class _PaperNav extends StatelessWidget {
  const _PaperNav({required this.index, required this.items, required this.onSelect, required this.onBreathe});

  final int index;
  final List<(IconData, IconData, String)> items;
  final ValueChanged<int> onSelect;
  final VoidCallback onBreathe;

  @override
  Widget build(BuildContext context) {
    final c = ppc(context);
    return Container(
      height: 76,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PpRadius.pill),
        border: PpShadow.edge(c),
        boxShadow: PpShadow.raised(c, lift: 1.1),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final slot = box.maxWidth / 5;
        final visual = index < 2 ? index : index + 1;
        return Stack(
          children: [
            // Sliding inset pill behind the active tab.
            AnimatedPositioned(
              duration: PpMotion.slow,
              curve: PpMotion.settle,
              left: visual * slot + 2,
              top: 0,
              bottom: 0,
              width: slot - 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.ground,
                  borderRadius: BorderRadius.circular(PpRadius.pill),
                  boxShadow: [
                    BoxShadow(color: c.shade.withValues(alpha: c.shade.a * 0.35), blurRadius: 10, offset: const Offset(0, 3)),
                    BoxShadow(color: c.highlight, blurRadius: 8, offset: const Offset(-3, -3)),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < 2; i++) _tab(context, i, slot),
                SizedBox(width: slot, child: Center(child: _BreatheTile(onTap: onBreathe))),
                for (var i = 2; i < 4; i++) _tab(context, i, slot),
              ],
            ),
          ],
        );
      }),
    );
  }

  Widget _tab(BuildContext context, int i, double slot) {
    final c = ppc(context);
    final selected = i == index;
    final color = selected ? c.brand : c.inkQuiet;
    return SizedBox(
      width: slot,
      child: Semantics(
        selected: selected,
        button: true,
        label: items[i].$3,
        child: SpringPress(
          onTap: () => onSelect(i),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: PpMotion.base,
                transitionBuilder: (child, a) => ScaleTransition(scale: Tween(begin: 0.7, end: 1.0).animate(a), child: child),
                child: Icon(selected ? items[i].$2 : items[i].$1, key: ValueKey(selected), color: color, size: 24),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: PpMotion.base,
                style: PpTheme.font(size: 11.5, weight: selected ? FontWeight.w700 : FontWeight.w500, color: color),
                child: Text(items[i].$3, maxLines: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreatheTile extends StatelessWidget {
  const _BreatheTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Start a breathing exercise',
      child: SpringPress(
        onTap: onTap,
        pressedScale: 0.86,
        child: const BrandTile(size: 52, icon: Icons.air_rounded),
      ),
    );
  }
}
