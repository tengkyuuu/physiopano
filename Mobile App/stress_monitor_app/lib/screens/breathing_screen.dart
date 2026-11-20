import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/physiopano_tokens.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../services/theme_provider.dart';
import '../motion/motion.dart';

// ============================================================================
//  Breathing exercise definitions
// ============================================================================

class _BreathingExercise {
  final String name;
  final String description;
  final IconData icon;
  final int inhale;
  final int hold;
  final int exhale;
  final int holdAfterExhale; // 0 = no second hold
  final Color accentColor;

  const _BreathingExercise({
    required this.name,
    required this.description,
    required this.icon,
    required this.inhale,
    required this.hold,
    required this.exhale,
    this.holdAfterExhale = 0,
    required this.accentColor,
  });

  int get cycleDuration => inhale + hold + exhale + holdAfterExhale;

  String get pattern {
    final parts = <String>['Inhale ${inhale}s'];
    if (hold > 0) parts.add('Hold ${hold}s');
    parts.add('Exhale ${exhale}s');
    if (holdAfterExhale > 0) parts.add('Hold ${holdAfterExhale}s');
    return parts.join(' \u2022 ');
  }
}

const _exercises = [
  _BreathingExercise(
    name: '4-7-8 Relaxing Breath',
    description: 'Clinically proven to reduce anxiety and promote sleep. '
        'Developed by Dr. Andrew Weil.',
    icon: Icons.nightlight_round,
    inhale: 4,
    hold: 7,
    exhale: 8,
    accentColor: AppColors.route2,
  ),
  _BreathingExercise(
    name: 'Box Breathing',
    description: 'Used by Navy SEALs for calm focus under pressure. '
        'Equal timing on all phases.',
    icon: Icons.crop_square_rounded,
    inhale: 4,
    hold: 4,
    exhale: 4,
    holdAfterExhale: 4,
    accentColor: AppColors.route4,
  ),
  _BreathingExercise(
    name: 'Deep Calm',
    description: 'Simple deep breathing for quick stress relief. '
        'Longer exhale activates the parasympathetic nervous system.',
    icon: Icons.self_improvement_rounded,
    inhale: 5,
    hold: 2,
    exhale: 7,
    accentColor: AppColors.route1,
  ),
  _BreathingExercise(
    name: 'Energizing Breath',
    description: 'Quick, balanced breathing to increase alertness '
        'and mental clarity.',
    icon: Icons.bolt_rounded,
    inhale: 3,
    hold: 3,
    exhale: 3,
    accentColor: AppColors.route3,
  ),
];

// ============================================================================
//  Main screen
// ============================================================================

class BreathingScreen extends StatefulWidget {
  const BreathingScreen({super.key});

  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen>
    with TickerProviderStateMixin {
  late AnimationController _breathController;
  late AnimationController _pulseController;
  late Animation<double> _breathAnimation;
  late Animation<double> _pulseAnimation;

  bool _isActive = false;
  int _totalSeconds = 0;
  Timer? _timer;
  int _cycleCount = 0;
  int _selectedExercise = 0;

  String _phase = 'Ready';
  double _phaseProgress = 0.0;

  /// 0..1 breath signal shared by the orb and Paño.
  final ValueNotifier<double> _breath = ValueNotifier(0.3);
  final ConfettiController _confetti = ConfettiController();

  void _syncBreath() {
    _breath.value = _isActive
        ? ((_breathAnimation.value - 0.3) / 0.7).clamp(0.0, 1.0)
        : (_pulseAnimation.value - 0.95) / 0.1 * 0.35 + 0.15;
  }

  _BreathingExercise get _exercise => _exercises[_selectedExercise];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseController.addListener(_syncBreath);
    _buildBreathAnimation();
  }

  void _buildBreathAnimation() {
    _breathController = AnimationController(
      vsync: this,
      duration: Duration(seconds: _exercise.cycleDuration),
    );

    final totalDur = _exercise.cycleDuration.toDouble();
    final inhaleWeight = _exercise.inhale / totalDur * 100;
    final holdWeight = _exercise.hold / totalDur * 100;
    final exhaleWeight = _exercise.exhale / totalDur * 100;
    final hold2Weight = _exercise.holdAfterExhale / totalDur * 100;

    final items = <TweenSequenceItem<double>>[
      TweenSequenceItem(
        tween: Tween(begin: 0.3, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: inhaleWeight,
      ),
    ];
    if (holdWeight > 0) {
      items.add(TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: holdWeight,
      ));
    }
    items.add(TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.3)
          .chain(CurveTween(curve: Curves.easeInOut)),
      weight: exhaleWeight,
    ));
    if (hold2Weight > 0) {
      items.add(TweenSequenceItem(
        tween: ConstantTween(0.3),
        weight: hold2Weight,
      ));
    }

    _breathAnimation = TweenSequence<double>(items).animate(_breathController);
    _breathController.addListener(_updatePhase);
    _breathController.addListener(_syncBreath);
  }

  void _selectExercise(int index) {
    if (_isActive) _stop();
    _breathController.dispose();
    setState(() {
      _selectedExercise = index;
      _phase = 'Ready';
      _phaseProgress = 0;
    });
    _buildBreathAnimation();
  }

  void _updatePhase() {
    if (!_isActive) return;
    final t = _breathController.value;
    final totalDur = _exercise.cycleDuration.toDouble();
    final inhaleEnd = _exercise.inhale / totalDur;
    final holdEnd = (_exercise.inhale + _exercise.hold) / totalDur;
    final exhaleEnd =
        (_exercise.inhale + _exercise.hold + _exercise.exhale) / totalDur;

    String newPhase;
    double progress;
    if (t < inhaleEnd) {
      newPhase = 'Inhale';
      progress = inhaleEnd > 0 ? t / inhaleEnd : 0;
    } else if (t < holdEnd) {
      newPhase = 'Hold';
      final denom = holdEnd - inhaleEnd;
      progress = denom > 0 ? (t - inhaleEnd) / denom : 0;
    } else if (t < exhaleEnd) {
      newPhase = 'Exhale';
      final denom = exhaleEnd - holdEnd;
      progress = denom > 0 ? (t - holdEnd) / denom : 0;
    } else {
      newPhase = 'Hold';
      final denom = 1.0 - exhaleEnd;
      progress = denom > 0 ? (t - exhaleEnd) / denom : 0;
    }

    if (newPhase != _phase || (progress - _phaseProgress).abs() > 0.02) {
      setState(() {
        _phase = newPhase;
        _phaseProgress = progress;
      });
    }
  }

  void _start() {
    setState(() {
      _isActive = true;
      _totalSeconds = 0;
      _cycleCount = 0;
      _phase = 'Inhale';
    });

    _breathController.repeat();
    _breathController.addStatusListener(_onCycleComplete);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _totalSeconds++);
    });
  }

  void _onCycleComplete(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() => _cycleCount++);
    }
  }

  void _stop() {
    final finishedCycles = _cycleCount;
    if (_isActive && finishedCycles > 0) {
      _confetti.fire(origin: const Offset(0.5, 0.45));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lovely. $finishedCycles calm ${finishedCycles == 1 ? 'cycle' : 'cycles'} done.')),
      );
    }
    _breathController.stop();
    _breathController.reset();
    _breathController.removeStatusListener(_onCycleComplete);
    _timer?.cancel();
    setState(() {
      _isActive = false;
      _phase = 'Ready';
      _phaseProgress = 0;
    });
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color get _phaseColor {
    switch (_phase) {
      case 'Inhale':
        return _exercise.accentColor;
      case 'Hold':
        return AppColors.emerald;
      case 'Exhale':
        return AppColors.route1;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  void dispose() {
    _breathController.dispose();
    _pulseController.dispose();
    _breath.dispose();
    _confetti.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final isConnected = ble.state == BleConnectionState.connected;
    final c = Theme.of(context).extension<PpColors>()!;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: ConfettiOverlay(
        controller: _confetti,
        child: AuroraBackground(
          calm: 1,
          child: SafeArea(
            child: Column(
              children: [
                // ---- Top bar ----
                Padding(
                  padding: const EdgeInsets.fromLTRB(PpSpace.gutter, 10, PpSpace.gutter, 0),
                  child: Row(
                    children: [
                      RoundPaperButton(icon: Icons.arrow_back_rounded, size: 46, tooltip: 'Back', onTap: () => Navigator.maybePop(context)),
                      const Spacer(),
                      AnimatedOpacity(
                        duration: PpMotion.base,
                        opacity: _isActive ? 1 : 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(PpRadius.pill),
                            border: PpShadow.edge(c),
                            boxShadow: PpShadow.raised(c, lift: 0.4),
                          ),
                          child: Text(_formatTime(_totalSeconds), style: PpTheme.data(context, size: 15)),
                        ),
                      ),
                    ],
                  ),
                ),

                // ---- Heading + exercise chips (collapse while active) ----
                ExpandReveal(
                  expanded: !_isActive,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(PpSpace.gutter, 18, PpSpace.gutter, 18),
                        child: Reveal(
                          child: PaperHeading(
                            eyebrow: 'A minute for you',
                            title: 'Breathe with me.',
                            lede: _exercise.pattern,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 64,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(PpSpace.gutter, 6, PpSpace.gutter, 12),
                          clipBehavior: Clip.none,
                          itemCount: _exercises.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (context, i) => PaperChip(
                            label: _exercises[i].name,
                            icon: _exercises[i].icon,
                            selected: i == _selectedExercise,
                            onTap: () => _selectExercise(i),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ---- The orb ----
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FadeThroughSwitcher(
                          child: Text(
                            _isActive ? '$_phase.' : 'Ready when you are.',
                            key: ValueKey(_isActive ? _phase : 'ready'),
                            style: t.headlineLarge,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox.square(
                          dimension: 280,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (_isActive) Ripples(color: c.brand.withValues(alpha: 0.6), size: 280),
                              MorphBlob(
                                size: 250,
                                breath: _breath,
                                colors: [c.brand, const Color(0xFF7FA6F5), const Color(0xFF3B7BF0)],
                                wobble: _isActive ? 0.06 : 0.035,
                              ),
                              // Phase progress ring hugs the orb.
                              AnimatedBuilder(
                                animation: _breath,
                                builder: (_, __) => CustomPaint(
                                  size: const Size.square(270),
                                  painter: _BreathCirclePainter(
                                    scale: 1,
                                    color: _isActive ? _phaseColor : c.brand,
                                    progress: _isActive ? _phaseProgress : 0,
                                    isDark: false,
                                  ),
                                ),
                              ),
                              PanoMascot(
                                mood: _isActive ? PanoMood.breathe : PanoMood.calm,
                                size: 104,
                                breath: _breath,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        AnimatedOpacity(
                          duration: PpMotion.base,
                          opacity: _isActive ? 1 : 0,
                          child: Text('CYCLE ${_cycleCount + 1}', style: PpTheme.eyebrow(context, color: c.inkQuiet)),
                        ),
                      ],
                    ),
                  ),
                ),

                // ---- Live readings while connected ----
                ExpandReveal(
                  expanded: isConnected && _isActive,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(PpSpace.gutter, 0, PpSpace.gutter, 14),
                    child: PaperCard(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _LiveStat(kind: SensorKind.heart, value: ble.hr.valid ? '${ble.hr.bpm}' : '--', unit: 'bpm'),
                          _LiveStat(
                            kind: SensorKind.hrv,
                            value: ble.stress.index >= 0 ? ble.stress.index.toStringAsFixed(0) : '--',
                            unit: 'index',
                          ),
                          _LiveStat(
                            kind: SensorKind.skin,
                            value: ble.gsr.microSiemens > 0 ? ble.gsr.microSiemens.toStringAsFixed(1) : '--',
                            unit: '\u00b5S',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ---- Start / Stop ----
                Padding(
                  padding: const EdgeInsets.fromLTRB(PpSpace.gutter, 4, PpSpace.gutter, 24),
                  child: PillButton(
                    label: _isActive ? 'I am done' : 'Begin',
                    icon: _isActive ? Icons.check_rounded : Icons.play_arrow_rounded,
                    tone: _isActive ? PillTone.paper : PillTone.primary,
                    onPressed: _isActive ? _stop : _start,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  Custom painter for the animated breathing circle
// ============================================================================

class _BreathCirclePainter extends CustomPainter {
  final double scale;
  final Color color;
  final double progress;
  final bool isDark;

  _BreathCirclePainter({
    required this.scale,
    required this.color,
    required this.progress,
    this.isDark = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2 - 10;
    final radius = maxRadius * scale.clamp(0.3, 1.0);

    // Background ring
    final bgPaint = Paint()
      ..color = const Color(0x1F242A32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BreathCirclePainter old) =>
      old.scale != scale ||
      old.color != color ||
      old.progress != progress ||
      old.isDark != isDark;
}

// ============================================================================
//  Small live stat widget
// ============================================================================

class _LiveStat extends StatelessWidget {
  final SensorKind kind;
  final String value;
  final String unit;

  const _LiveStat({
    required this.kind,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<PpColors>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SensorGlyph(kind: kind, size: 30),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: PpTheme.data(context, size: 17)),
            Text(unit, style: PpTheme.font(size: 11, color: c.inkMuted)),
          ],
        ),
      ],
    );
  }
}
