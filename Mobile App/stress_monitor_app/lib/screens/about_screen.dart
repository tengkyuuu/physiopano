import 'package:flutter/material.dart';
import '../theme/paper.dart';
import '../theme/physiopano_tokens.dart';
import '../services/theme_provider.dart';

/// About screen — project info, sensor descriptions, how to read "your usual".
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor ?? 
                         Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'About',
          style: TextStyle(
            color: Theme.of(context).textTheme.titleLarge?.color ??
                   Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Header ----
            Center(
              child: Column(
                children: [
                  const BrandTile(size: 88),
                  const SizedBox(height: 16),
                  Text(
                    'PHYSIOPAÑO',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.titleLarge?.color ?? 
                             Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'v1.0.0',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ---- Thesis Info ----
            _SectionCard(
              icon: Icons.school_rounded,
              title: 'Thesis Project',
              children: [
                Text(
                  'Wearable Technology for Personalized Well-Being '
                  'Among University Students: Development and Validation '
                  'of Physiological Signals',
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                    color: Theme.of(context).textTheme.bodyMedium?.color ??
                           Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                const _InfoRow(label: 'Authors', value: 'Calunsag, Manubag & Opao'),
                const _InfoRow(label: 'Platform', value: 'ESP32 WROOM-32'),
                const _InfoRow(label: 'Date', value: 'March 2026'),
              ],
            ),
            const SizedBox(height: 12),

            // ---- Sensors ----
            const _SectionCard(
              icon: Icons.sensors_rounded,
              title: 'Integrated Sensors',
              children: [
                _SensorInfo(
                  name: 'MAX30102',
                  desc: 'PPG heart rate sensor — measures BPM via '
                      'infrared light through the skin.',
                  icon: Icons.favorite,
                  color: Colors.red,
                ),
                SizedBox(height: 10),
                _SensorInfo(
                  name: 'Grove GSR v1.2',
                  desc: 'Galvanic skin response — measures skin conductance '
                      '(electrodermal activity) related to sweat gland activation.',
                  icon: Icons.water_drop,
                  color: PpAccent.mint,
                ),
                SizedBox(height: 10),
                _SensorInfo(
                  name: 'MLX90614',
                  desc: 'Infrared temperature sensor — measures skin '
                      'surface temperature without contact.',
                  icon: Icons.thermostat,
                  color: PpAccent.sun,
                ),
                SizedBox(height: 10),
                _SensorInfo(
                  name: 'MPU6050',
                  desc: '6-axis accelerometer & gyroscope — detects '
                      'motion artifacts that can affect readings.',
                  icon: Icons.vibration,
                  color: PpAccent.sky,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ---- Your usual guide ----
            const _SectionCard(
              icon: Icons.psychology_rounded,
              title: 'Reading "your usual"',
              children: [
                _StressLevelInfo(
                  label: 'Within your usual (0–33)',
                  desc: 'Your signals are close to how they normally are for you '
                      'at this time of day.',
                  color: AppColors.levelLow,
                ),
                SizedBox(height: 8),
                _StressLevelInfo(
                  label: 'A little different (34–66)',
                  desc: 'Somewhat away from your usual. Often a coffee, a walk or '
                      'a busy hour. A slow breath can help.',
                  color: AppColors.levelMid,
                ),
                SizedBox(height: 8),
                _StressLevelInfo(
                  label: 'Different from your usual (67–100)',
                  desc: 'Clearly away from your usual right now. If it keeps '
                      'happening over several days, the app offers a short check-in.',
                  color: AppColors.levelHigh,
                ),
                SizedBox(height: 8),
                _StressLevelInfo(
                  label: 'What it is not',
                  desc: 'Not a stress score and not a diagnosis. It only compares '
                      'you with yourself.',
                  color: AppColors.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ---- HRV Info ----
            const _SectionCard(
              icon: Icons.timeline_rounded,
              title: 'Understanding HRV',
              children: [
                Text(
                  'Heart Rate Variability (HRV) measures the variation in '
                  'time between heartbeats. Higher HRV generally indicates '
                  'better cardiovascular fitness and stress resilience.',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                SizedBox(height: 8),
                _InfoRow(
                    label: 'RMSSD',
                    value: 'Root mean square of successive IBI differences'),
                _InfoRow(
                    label: 'SDNN',
                    value: 'Standard deviation of IBI intervals'),
                _InfoRow(
                    label: 'pNN50',
                    value: '% of successive IBIs differing by >50ms'),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ---- Helper widgets ----

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppColors.emerald, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.titleMedium?.color ??
                           Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SensorInfo extends StatelessWidget {
  final String name;
  final String desc;
  final IconData icon;
  final Color color;

  const _SensorInfo({
    required this.name,
    required this.desc,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StressLevelInfo extends StatelessWidget {
  final String label;
  final String desc;
  final Color color;

  const _StressLevelInfo({
    required this.label,
    required this.desc,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
