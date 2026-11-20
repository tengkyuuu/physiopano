import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/physiopano_tokens.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/ble_service.dart';
import '../../services/database_service.dart';
import '../../services/baseline_service.dart';
import '../../services/sync_service.dart';
import '../../services/theme_provider.dart';
import '../../motion/motion.dart';
import '../outcome_sharing_screen.dart';

/// Onboarding flow:
///   1. Welcome
///   2. Device pairing (skippable)
///   3. Emergency contact — only if none was given at sign-up
///   4. Baseline calibration (skippable)
///
/// Finishing calls [onComplete]; the session gate in main.dart then shows the
/// app. This screen never navigates away from the root itself.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.onComplete});

  /// Called once onboarding is saved as complete.
  final VoidCallback? onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _currentPage = 0;
  bool _finishing = false;

  /// null while the saved profile is loading.
  bool? _askForContact;

  // Emergency contact fields (prefilled from anything already saved).
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  int get _pageCount => _askForContact == true ? 4 : 3;

  @override
  void initState() {
    super.initState();
    _loadSavedContact();
  }

  Future<void> _loadSavedContact() async {
    final auth = context.read<AuthService>();
    final db = context.read<DatabaseService>();
    final s = await db.getSettings(auth.userId);
    if (!mounted) return;
    String v(String k) => (s?[k] as String? ?? '').trim();
    _nameCtrl.text = v('emergency_name');
    _emailCtrl.text = v('emergency_email');
    _phoneCtrl.text = v('emergency_phone');
    // A contact counts as given when it has a name and a way to reach them.
    final hasContact = _nameCtrl.text.isNotEmpty && (_emailCtrl.text.isNotEmpty || _phoneCtrl.text.isNotEmpty);
    setState(() => _askForContact = !hasContact);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _pageCount - 1) {
      _pageCtrl.nextPage(duration: PpMotion.slow, curve: PpMotion.ease);
    }
  }

  Future<void> _completeOnboarding() async {
    if (_finishing) return;
    _finishing = true;
    final auth = context.read<AuthService>();
    final db = context.read<DatabaseService>();
    final sync = context.read<SyncService>();
    if (auth.userId.isNotEmpty) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OutcomeSharingScreen(uid: auth.userId, onboarding: true),
      ));
    }
    if (!mounted) return;

    // Merge-save: only write the contact if it was asked for here, so a
    // contact given at sign-up is never overwritten.
    await db.saveSettings(auth.userId, {
      if (_askForContact == true) ...{
        'emergency_name': _nameCtrl.text.trim(),
        'emergency_email': _emailCtrl.text.trim(),
        'emergency_phone': _phoneCtrl.text.trim(),
      },
      'onboarding_complete': 1,
    });

    sync.syncProfileNow();
    sync.startListening();

    if (!mounted) return;
    widget.onComplete?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_askForContact == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final pages = <Widget>[
      _WelcomePage(onNext: _next),
      _DevicePairingPage(onNext: _next),
      if (_askForContact == true)
        _EmergencyContactPage(
          nameCtrl: _nameCtrl,
          emailCtrl: _emailCtrl,
          phoneCtrl: _phoneCtrl,
          onNext: _next,
        ),
      _BaselineCalibrationPage(onComplete: _completeOnboarding),
    ];
    return Scaffold(
      backgroundColor: AppColors.deepBlack,
      body: AuroraBackground(
        child: SafeArea(
        child: Column(
          children: [
            // Progress: one pill per step; the current one stretches.
            Padding(
              padding: const EdgeInsets.all(16),
              child: Semantics(
                label: 'Step ${_currentPage + 1} of ${pages.length}',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(pages.length, (i) {
                    return AnimatedContainer(
                      duration: PpMotion.slow,
                      curve: PpMotion.settle,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == i ? 28 : 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _currentPage >= i ? AppColors.emerald : AppColors.border,
                        borderRadius: BorderRadius.circular(PpRadius.pill),
                      ),
                    );
                  }),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: pages,
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ---- Page 1: Welcome ----

class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(PpSpace.gutter, 12, PpSpace.gutter, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Reveal(
            child: Align(
              alignment: Alignment.centerLeft,
              child: PanoMascot(mood: PanoMood.wave, size: 132, prop: PanoProp.heart),
            ),
          ),
          const SizedBox(height: 18),
          Reveal(
            index: 1,
            child: PaperHeading(
              eyebrow: 'Welcome to PHYSIOPAÑO',
              title: 'Hi, I am Paño.',
              titleStyle: Theme.of(context).textTheme.displaySmall,
              lede: 'I live in your wearable and notice how your body is doing, so you can catch hard days a little earlier.',
            ),
          ),
          const SizedBox(height: 26),
          const Reveal(
            index: 2,
            child: InfoNote(
              icon: Icons.lock_outline_rounded,
              title: 'Yours, on this phone',
              body: 'Your readings and check-ins stay on this device unless you choose to share them.',
            ),
          ),
          const SizedBox(height: 30),
          Reveal(index: 3, child: _NextButton(label: 'Let us set things up', onPressed: onNext)),
        ],
      ),
    );
  }
}

// ---- Page 2: Device Pairing ----

class _DevicePairingPage extends StatelessWidget {
  final VoidCallback onNext;
  const _DevicePairingPage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final isConnected = ble.state == BleConnectionState.connected;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          WristbandArt(size: 220, live: isConnected, searching: !isConnected),
          const SizedBox(height: 16),
          const Text(
            'Pair Your Device',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isConnected
                ? 'Device connected successfully!'
                : 'Power on your PHYSIOPAÑO device and tap scan.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (!isConnected) ...[
            // Status
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (ble.state == BleConnectionState.scanning ||
                      ble.state == BleConnectionState.connecting)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      ble.statusMessage,
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: ble.state == BleConnectionState.scanning
                    ? null
                    : () => ble.startScan(),
                icon: const Icon(Icons.bluetooth_searching, size: 20),
                label: const Text('Scan for Device'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Found devices
            if (ble.scanResults.isNotEmpty)
              ...ble.scanResults.map((d) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading:
                          const Icon(Icons.watch, color: AppColors.emerald),
                      title: Text(d.platformName.isNotEmpty
                          ? d.platformName
                          : 'Unknown'),
                      subtitle: Text(d.remoteId.toString(),
                          style: const TextStyle(fontSize: 11)),
                      onTap: () => ble.connectToDevice(d),
                    ),
                  )),

            const Spacer(),
            // Skip option
            TextButton(
              onPressed: onNext,
              child: Text(
                'Skip for now',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade600),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('PHYSIOPAÑO device is connected and ready!'),
                  ),
                ],
              ),
            ),
            const Spacer(),
            _NextButton(label: 'Continue', onPressed: onNext),
          ],
        ],
      ),
    );
  }
}

// ---- Page 3: Emergency Contact ----

class _EmergencyContactPage extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController phoneCtrl;
  final VoidCallback onNext;

  const _EmergencyContactPage({
    required this.nameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(
            Icons.contact_emergency_rounded,
            size: 56,
            color: AppColors.emerald,
          ),
          const SizedBox(height: 20),
          const Text(
            'Emergency Contact',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Someone you trust. PHYSIOPAÑO never contacts them on its own; '
            'they are kept here so you can reach them quickly.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          _FieldBox(
            controller: nameCtrl,
            label: 'Contact Name',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 14),
          _FieldBox(
            controller: emailCtrl,
            label: 'Contact Email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          _FieldBox(
            controller: phoneCtrl,
            label: 'Contact Phone',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 32),
          _NextButton(label: 'Continue', onPressed: onNext),
        ],
      ),
    );
  }
}

// ---- Page 4: Baseline Calibration ----

class _BaselineCalibrationPage extends StatefulWidget {
  final VoidCallback onComplete;
  const _BaselineCalibrationPage({required this.onComplete});

  @override
  State<_BaselineCalibrationPage> createState() =>
      _BaselineCalibrationPageState();
}

class _BaselineCalibrationPageState extends State<_BaselineCalibrationPage> {
  static const int _calibrationSeconds = 300; // 5 minutes
  int _elapsed = 0;
  bool _started = false;
  bool _done = false;
  Timer? _timer;

  void _start() {
    final ble = context.read<BleService>();
    final baseline = context.read<BaselineService>();

    if (ble.state != BleConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect your device first.'),
        ),
      );
      return;
    }

    baseline.startCalibration();
    setState(() => _started = true);

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _elapsed++);
      if (_elapsed >= _calibrationSeconds) {
        t.cancel();
        final auth = context.read<AuthService>();
        baseline.completeCalibration(auth.userId);
        setState(() => _done = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  double get _progress => _elapsed / _calibrationSeconds;
  String get _timeRemaining {
    final remaining = _calibrationSeconds - _elapsed;
    final m = remaining ~/ 60;
    final s = remaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.tune_rounded,
            size: 56,
            color: AppColors.emerald,
          ),
          const SizedBox(height: 20),
          const Text(
            'Baseline Calibration',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _done
                ? 'Calibration complete! Your baseline has been saved.'
                : _started
                    ? 'Stay relaxed while we record your baseline readings. '
                        'Keep still and breathe normally.'
                    : 'We need 5 minutes of resting data to establish your '
                        'personal baseline for accurate stress detection.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (_started && !_done) ...[
            // Progress ring
            SizedBox(
              width: 160,
              height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 8,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation(AppColors.emerald),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _timeRemaining,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w300,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Text(
                        'remaining',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '${(_progress * 100).toStringAsFixed(0)}% complete',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (_done) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: PpAccent.mint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: PpAccent.mint),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Baseline calibration saved successfully!'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _NextButton(
              label: 'Start Using PHYSIOPAÑO',
              onPressed: widget.onComplete,
            ),
          ],
          if (!_started) ...[
            _NextButton(label: 'Start Calibration', onPressed: _start),
            const SizedBox(height: 16),
            TextButton(
              onPressed: widget.onComplete,
              child: const Text(
                'Skip for now',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- Shared widgets ----

class _NextButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _NextButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) =>
      PillButton(label: label, trailingIcon: Icons.arrow_forward_rounded, onPressed: onPressed);
}

class _FieldBox extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;

  const _FieldBox({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        filled: true,
        fillColor: AppColors.cardDarkAlt,
      ),
    );
  }
}
