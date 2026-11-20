import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'motion_lab_screen.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/baseline_service.dart';
import '../services/ble_service.dart';
import '../services/theme_provider.dart';
import '../services/change_detector.dart';
import '../services/sync_service.dart';
import '../services/referral_service.dart';
import '../models/referral.dart';
import '../models/support_station.dart';
import '../theme/physiopano_tokens.dart';
import 'outcome_sharing_screen.dart';

/// Settings screen — profile, emergency contact, device, notifications,
/// baseline recalibration, sign out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _displayNameCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyEmailCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  bool _notifyHighStress = true;
  bool _notifyChronic = true;
  bool _notifyBattery = true;
  bool _notifyReconnect = true;
  bool _incognitoMode = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final auth = context.read<AuthService>();
    final db = context.read<DatabaseService>();
    final settings = await db.getSettings(auth.userId);

    if (settings != null) {
      _displayNameCtrl.text = settings['display_name'] as String? ?? '';
      _studentIdCtrl.text = settings['student_id'] as String? ?? '';
      _emergencyNameCtrl.text = settings['emergency_name'] as String? ?? '';
      _emergencyEmailCtrl.text = settings['emergency_email'] as String? ?? '';
      _emergencyPhoneCtrl.text = settings['emergency_phone'] as String? ?? '';
      _notifyHighStress = (settings['notify_high_stress'] as int?) == 1;
      _notifyChronic = (settings['notify_chronic'] as int?) == 1;
      _notifyBattery = (settings['notify_battery'] as int?) == 1;
      _notifyReconnect = (settings['notify_reconnect'] as int?) == 1;
      _incognitoMode = (settings['incognito_mode'] as int?) == 1;
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  /// Switches apply immediately (Android convention); only one column changes.
  Future<void> _savePref(String key, bool value) async {
    final auth = context.read<AuthService>();
    await context.read<DatabaseService>().saveSettings(auth.userId, {key: value ? 1 : 0});
  }

  Future<void> _save() async {
    final auth = context.read<AuthService>();
    final db = context.read<DatabaseService>();

    await db.saveSettings(auth.userId, {
      'display_name': _displayNameCtrl.text.trim(),
      'student_id': _studentIdCtrl.text.trim(),
      'emergency_name': _emergencyNameCtrl.text.trim(),
      'emergency_email': _emergencyEmailCtrl.text.trim(),
      'emergency_phone': _emergencyPhoneCtrl.text.trim(),
      'notify_high_stress': _notifyHighStress ? 1 : 0,
      'notify_chronic': _notifyChronic ? 1 : 0,
      'notify_battery': _notifyBattery ? 1 : 0,
      'notify_reconnect': _notifyReconnect ? 1 : 0,
      'incognito_mode': _incognitoMode ? 1 : 0,
      'onboarding_complete': 1,
    });

    // Keep the account name in step so greetings show the new name.
    await auth.updateDisplayName(_displayNameCtrl.text);
    if (!mounted) return;
    unawaited(context.read<SyncService>().syncProfileNow());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile saved')),
    );
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _studentIdCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyEmailCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final baseline = context.watch<BaselineService>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? 
                         Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Settings',
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color ??
                   Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'Save',
              style: TextStyle(
                color: AppColors.emerald,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- Profile ----
                  const _SectionHeader(title: 'Profile', icon: Icons.person_outline),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _Field(
                            controller: _displayNameCtrl,
                            label: 'Display Name',
                          ),
                          const SizedBox(height: 12),
                          _Field(
                            controller: _studentIdCtrl,
                            label: 'Student ID',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ---- Emergency Contact ----
                  const _SectionHeader(
                    title: 'Emergency Contact',
                    icon: Icons.contact_emergency_outlined,
                  ),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _Field(
                            controller: _emergencyNameCtrl,
                            label: 'Contact Name',
                          ),
                          const SizedBox(height: 12),
                          _Field(
                            controller: _emergencyEmailCtrl,
                            label: 'Contact Email',
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 12),
                          _Field(
                            controller: _emergencyPhoneCtrl,
                            label: 'Contact Phone',
                            keyboardType: TextInputType.phone,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ---- Device ----
                  const _SectionHeader(
                    title: 'Device',
                    icon: Icons.watch_rounded,
                  ),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            ble.state == BleConnectionState.connected
                                ? Icons.bluetooth_connected
                                : Icons.bluetooth_disabled,
                            color: ble.state == BleConnectionState.connected
                                ? PpAccent.mint
                                : Colors.grey,
                          ),
                          title: const Text('Connection Status'),
                          trailing: Text(
                            ble.state == BleConnectionState.connected
                                ? 'Connected'
                                : 'Disconnected',
                            style: TextStyle(
                              color: ble.state == BleConnectionState.connected
                                  ? PpAccent.mint
                                  : Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (ble.stress.battery > 0)
                          ListTile(
                            leading: Icon(
                              ble.stress.battery > 20
                                  ? Icons.battery_std
                                  : Icons.battery_alert,
                              color: ble.stress.battery > 20
                                  ? PpAccent.mint
                                  : Colors.red,
                            ),
                            title: const Text('Battery'),
                            trailing: Text('${ble.stress.battery}%'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ---- Baseline ----
                  const _SectionHeader(
                    title: 'Calibration',
                    icon: Icons.tune_rounded,
                  ),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            baseline.isCalibrated
                                ? Icons.check_circle
                                : Icons.pending,
                            color: baseline.isCalibrated
                                ? PpAccent.mint
                                : PpAccent.sun,
                          ),
                          title: const Text('Baseline Status'),
                          trailing: Text(
                            baseline.isCalibrated
                                ? 'Calibrated'
                                : 'Not calibrated',
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.refresh,
                              color: AppColors.emerald),
                          title: const Text('Recalibrate Baseline'),
                          subtitle: const Text(
                            'Requires 5 min of rest with device connected',
                            style: TextStyle(fontSize: 12),
                          ),
                          onTap: () async {
                            final auth = context.read<AuthService>();
                            await baseline.clearBaseline(auth.userId);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Baseline cleared. Return to onboarding to recalibrate.',
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ---- Your usual (personal baseline) ----
                  const _SectionHeader(
                    title: 'Your usual',
                    icon: Icons.timeline_rounded,
                  ),
                  const _YourUsualCard(),
                  const SizedBox(height: 16),

                  // ---- Sharing (consent, revocable) ----
                  const _SectionHeader(
                    title: 'Sharing',
                    icon: Icons.lock_person_outlined,
                  ),
                  const _SharingCard(),
                  ListTile(
                    leading: const Icon(Icons.insights_outlined),
                    title: const Text('Outcome sharing'),
                    subtitle: const Text('Choose whether to contribute to group reports'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      final uid = context.read<AuthService>().userId;
                      if (uid.isEmpty) return;
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => OutcomeSharingScreen(uid: uid),
                      ));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: const Text('Meet Paño'),
                    subtitle: const Text('The motion and art kit behind the app'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MotionLabScreen()),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ---- Notifications ----
                  const _SectionHeader(
                    title: 'Notifications',
                    icon: Icons.notifications_outlined,
                  ),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Changes from your usual'),
                          subtitle: const Text(
                              'A gentle note after 3 or more days away from your usual'),
                          value: _notifyHighStress,
                          onChanged: (v) {
                            setState(() => _notifyHighStress = v);
                            _savePref('notify_high_stress', v);
                          },
                          activeThumbColor: AppColors.emerald,
                        ),
                        SwitchListTile(
                          title: const Text('Low band battery'),
                          subtitle: const Text('When your band drops to 15% or less'),
                          value: _notifyBattery,
                          onChanged: (v) {
                            setState(() => _notifyBattery = v);
                            _savePref('notify_battery', v);
                          },
                          activeThumbColor: AppColors.emerald,
                        ),
                        SwitchListTile(
                          title: const Text('Band reconnected'),
                          subtitle: const Text('When your band reconnects after dropping out'),
                          value: _notifyReconnect,
                          onChanged: (v) {
                            setState(() => _notifyReconnect = v);
                            _savePref('notify_reconnect', v);
                          },
                          activeThumbColor: AppColors.emerald,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ---- Privacy ----
                  const _SectionHeader(
                    title: 'Privacy & Data',
                    icon: Icons.security_rounded,
                  ),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Keep data on this phone'),
                          subtitle:
                              const Text('Pause cloud sync. Nothing leaves this phone until you turn this off.'),
                          value: _incognitoMode,
                          onChanged: (v) {
                            setState(() => _incognitoMode = v);
                            _savePref('incognito_mode', v);
                          },
                          activeThumbColor: AppColors.emerald,
                        ),
                        ListTile(
                          leading: const Icon(Icons.backup,
                              color: PpAccent.sun),
                          title: const Text('Backup Database',
                              style: TextStyle(color: PpAccent.sun)),
                          subtitle: const Text(
                              'Copy raw DB file to device storage for recovery'),
                          onTap: () => _backupDatabase(),
                        ),
                        ListTile(
                          leading: const Icon(Icons.delete_forever,
                              color: Colors.red),
                          title: const Text('Delete My Data',
                              style: TextStyle(color: Colors.red)),
                          subtitle:
                              const Text('Wipes all local and cloud data'),
                          onTap: () => _confirmWipeData(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ---- Sign out ----
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final auth = context.read<AuthService>();
                        // The root session gate shows Login once auth is null;
                        // just close anything stacked above it.
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        await auth.signOut();
                      },
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text(
                        'Sign Out',
                        style: TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.red.shade200),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Future<void> _backupDatabase() async {
    try {
      // Source: app's private SQLite database
      final dbDir = await getDatabasesPath();
      final srcPath = p.join(dbDir, 'stress_monitor.db');
      final src = File(srcPath);
      if (!await src.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database file not found.')),
        );
        return;
      }

      // Copy to app's cache dir first (always writable, no permissions needed)
      final cacheDir = await getTemporaryDirectory();
      final destPath = p.join(cacheDir.path, 'stress_backup.db');
      await src.copy(destPath);

      // Share via Android share sheet — user can save to Drive, Gmail, Files, etc.
      // This bypasses Android 11+ scoped storage restrictions entirely.
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(destPath, mimeType: 'application/octet-stream')],
          subject: 'stress_backup.db',
          text: 'PHYSIOPAÑO database backup',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup failed: $e')),
      );
    }
  }

  Future<void> _confirmWipeData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete everything?'),
        content: const Text(
          'This will permanently delete ALL your physiological data, settings, '
          'and baselines from both this device and the cloud. This action cannot '
          'be undone.\n\nAre you absolutely sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Wipe Data', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _loading = true);
      try {
        final auth = context.read<AuthService>();
        final db = context.read<DatabaseService>();
        final uid = auth.userId;

        // Cloud first (profile, sessions, readings, then the login). If that
        // fails, nothing local is touched and the reason is shown.
        final error = await auth.deleteAccount();
        if (error != null) {
          if (!mounted) return;
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
          return;
        }
        await db.wipeAllUserData(uid);

        // Auth is now signed out; the root session gate shows Login.
        if (!mounted) return;
        Navigator.of(context).popUntil((r) => r.isFirst);
      } catch (e) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error wiping data: $e')),
        );
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.emerald),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleMedium?.color ??
                     Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;

  const _Field({
    required this.controller,
    required this.label,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey.shade900
            : Colors.grey.shade50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}


/// Personal-baseline status and controls.
class _YourUsualCard extends StatelessWidget {
  const _YourUsualCard();

  @override
  Widget build(BuildContext context) {
    final cd = context.watch<ChangeDetector>();
    final a = cd.assessment;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.timeline_rounded, color: AppColors.emerald),
            title: Text(cd.isSynthetic ? 'Demo history (synthetic)' : 'Your baseline'),
            subtitle: Text(a?.summary ?? 'Learning your usual.'),
            isThreeLine: true,
          ),
          ListTile(
            leading: const Icon(Icons.science_outlined, color: AppColors.textSecondary),
            title: const Text('Load demo history'),
            subtitle: const Text(
              'Replaces your baseline with 14 synthetic days, labelled as demo data',
              style: TextStyle(fontSize: 12),
            ),
            onTap: () async {
              await context.read<ChangeDetector>().seedDemoHistory();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Demo history loaded. It is synthetic, not your data.')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
            title: const Text('Forget my baseline'),
            subtitle: const Text(
              'Deletes it from this phone and starts learning again',
              style: TextStyle(fontSize: 12),
            ),
            onTap: () async {
              await context.read<ChangeDetector>().resetHistory();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Baseline forgotten. Learning your usual from today.')),
              );
            },
          ),
        ],
      ),
    );
  }
}


/// Every referral the person has made, what it shares, until when, and a
/// one-tap way to stop sharing. Employers are a permanent locked-off row.
class _SharingCard extends StatelessWidget {
  const _SharingCard();

  static String _date(DateTime d) =>
      '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';

  Widget _sharingSummary(ReferralView referral, DateTime now) {
    final stopped = referral.withdrawnAt;
    if (stopped != null) {
      return Text('You stopped sharing on ${_date(stopped)}.');
    }
    if (!referral.sharingActive(now)) {
      return Text('Sharing ended on ${_date(referral.expiresAt)}.');
    }
    return StreamBuilder<bool>(
      stream: referral.kind == ReferralKind.referral
          ? ReferralService().hasFollowUp(referral.id)
          : null,
      builder: (context, snapshot) {
        final streams = [
          ...referral.streams.map(ReferralView.streamLabel),
          if (snapshot.data == true) 'your follow-up',
        ];
        final summary = streams.isEmpty ? 'the referral request' : streams.join(', ');
        return Text(
          'Your navigator can see $summary until ${_date(referral.expiresAt)}.',
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthService>().userId;
    final c = Theme.of(context).extension<PpColors>()!;
    return Card(
      child: StreamBuilder<List<ReferralView>>(
        stream: uid.isEmpty ? const Stream.empty() : ReferralService().mine(uid),
        builder: (context, snap) {
          final items = snap.data ?? const <ReferralView>[];
          final now = DateTime.now();
          return Column(
            children: [
              if (snap.connectionState == ConnectionState.waiting && items.isEmpty)
                const ListTile(title: Text('Loading what you share…')),
              if (snap.hasError)
                const ListTile(
                  title: Text('Could not load your referrals'),
                  subtitle: Text('Check your connection. Nothing changes until you are back online.'),
                ),
              if (!snap.hasError && snap.connectionState != ConnectionState.waiting && items.isEmpty)
                const ListTile(
                  title: Text('Shared with: nobody'),
                  subtitle: Text('When you ask for a referral, it appears here with what it shares.'),
                ),
              for (final r in items)
                ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: c.route(r.station),
                    child: Text('${SupportStation.of(r.station).number}',
                        style: TextStyle(color: c.onRoute(r.station), fontWeight: FontWeight.w800)),
                  ),
                  title: Text(
                    '${r.kind == ReferralKind.urgent ? 'Call-back request' : SupportStation.of(r.station).name}'
                    ' · ${switch (r.status) { ReferralStatus.pending => 'waiting', ReferralStatus.accepted => 'accepted', ReferralStatus.closed => 'closed' }}',
                  ),
                  subtitle: _sharingSummary(r, now),
                  trailing: r.sharingActive(now)
                      ? TextButton(
                          onPressed: () async {
                            try {
                              await ReferralService().withdraw(r.id);
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Could not stop sharing. Check your connection and try again.')),
                              );
                              return;
                            }
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Sharing stopped. The navigator can no longer see it.')),
                            );
                          },
                          child: const Text('Stop sharing'),
                        )
                      : null,
                ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Your employer'),
                subtitle: const Text('Never. Employers cannot be added.'),
                trailing: Icon(Icons.lock_outline, color: c.inkMuted),
              ),
            ],
          );
        },
      ),
    );
  }
}
