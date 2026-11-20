/// Data models for the StressMonitor BLE GATT characteristics.
///
/// Each model maps 1:1 to the JSON payload sent by the ESP32 firmware v4.0.
/// UUIDs and field names are kept in sync with the firmware header comments.
library;

import 'dart:convert';
import 'dart:math' as math;

// ==========================================================================
//  BLE UUIDs — must match firmware #defines exactly
// ==========================================================================
class BleUuids {
  static const String service = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String charHR = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  static const String charHRV = "beb5483e-36e1-4688-b7f5-ea07361b26a9";
  static const String charGSR = "beb5483e-36e1-4688-b7f5-ea07361b26aa";
  static const String charTemp = "beb5483e-36e1-4688-b7f5-ea07361b26ab";
  static const String charMotion = "beb5483e-36e1-4688-b7f5-ea07361b26ac";
  static const String charStress = "beb5483e-36e1-4688-b7f5-ea07361b26ad";
}

// ==========================================================================
//  HR Characteristic: {"bpm":XX,"valid":true/false,"sqi":X.XX}
// ==========================================================================
class HRData {
  final int bpm;
  final bool valid;
  final double sqi;
  final DateTime timestamp;

  const HRData({
    required this.bpm,
    required this.valid,
    required this.sqi,
    required this.timestamp,
  });

  factory HRData.fromJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return HRData(
      bpm: (m['bpm'] as num?)?.toInt() ?? 0,
      valid: m['valid'] as bool? ?? false,
      sqi: (m['sqi'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'bpm': bpm,
        'valid': valid,
        'sqi': sqi,
        'ts': timestamp.millisecondsSinceEpoch,
      };

  static HRData empty() => HRData(
        bpm: 0,
        valid: false,
        sqi: 0.0,
        timestamp: DateTime.now(),
      );
}

// ==========================================================================
//  HRV Characteristic: {"rmssd":XX.X,"sdnn":XX.X,"pnn50":XX.X}
// ==========================================================================
class HRVData {
  final double rmssd;
  final double sdnn;
  final double pnn50;
  final DateTime timestamp;

  const HRVData({
    required this.rmssd,
    required this.sdnn,
    required this.pnn50,
    required this.timestamp,
  });

  factory HRVData.fromJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return HRVData(
      rmssd: (m['rmssd'] as num?)?.toDouble() ?? -1.0,
      sdnn: (m['sdnn'] as num?)?.toDouble() ?? -1.0,
      pnn50: (m['pnn50'] as num?)?.toDouble() ?? -1.0,
      timestamp: DateTime.now(),
    );
  }

  bool get valid => rmssd >= 0;

  Map<String, dynamic> toMap() => {
        'rmssd': rmssd,
        'sdnn': sdnn,
        'pnn50': pnn50,
        'ts': timestamp.millisecondsSinceEpoch,
      };

  static HRVData empty() => HRVData(
        rmssd: -1,
        sdnn: -1,
        pnn50: -1,
        timestamp: DateTime.now(),
      );
}

// ==========================================================================
//  GSR Characteristic: {"us":XX.XX,"raw":XXXX}
// ==========================================================================
class GSRData {
  final double microSiemens;
  final int raw;
  final DateTime timestamp;

  const GSRData({
    required this.microSiemens,
    required this.raw,
    required this.timestamp,
  });

  factory GSRData.fromJson(String raw_) {
    final m = jsonDecode(raw_) as Map<String, dynamic>;
    return GSRData(
      microSiemens: ((m['us'] as num?) ??
                  (m['microSiemens'] as num?) ??
                  (m['resistance'] as num?) ??
                  (m['conductance'] as num?))
              ?.toDouble() ??
          0.0,
      raw: ((m['raw'] as num?) ?? (m['adc'] as num?))?.toInt() ?? 0,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'us': microSiemens,
        'raw': raw,
        'ts': timestamp.millisecondsSinceEpoch,
      };

  static GSRData empty() => GSRData(
        microSiemens: 0,
        raw: 0,
        timestamp: DateTime.now(),
      );
}

// ==========================================================================
//  Temperature Characteristic: {"skin":XX.XX,"ambient":XX.XX}
// ==========================================================================
class TempData {
  final double skin;
  final double ambient;
  final DateTime timestamp;

  const TempData({
    required this.skin,
    required this.ambient,
    required this.timestamp,
  });

  factory TempData.fromJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return TempData(
      skin: ((m['skin'] as num?) ??
                  (m['obj'] as num?) ??
                  (m['object'] as num?) ??
                  (m['temp'] as num?) ??
                  (m['temperature'] as num?))
              ?.toDouble() ??
          0.0,
      ambient:
          ((m['ambient'] as num?) ?? (m['amb'] as num?) ?? (m['room'] as num?))
                  ?.toDouble() ??
              0.0,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'skin': skin,
        'ambient': ambient,
        'ts': timestamp.millisecondsSinceEpoch,
      };

  static TempData empty() => TempData(
        skin: 0,
        ambient: 0,
        timestamp: DateTime.now(),
      );
}

// ==========================================================================
//  Motion Characteristic: {"ax":X.XXX,"ay":X.XXX,"az":X.XXX,"mag":X.XXX}
// ==========================================================================
class MotionData {
  final double ax;
  final double ay;
  final double az;
  final double mag;
  final DateTime timestamp;

  const MotionData({
    required this.ax,
    required this.ay,
    required this.az,
    required this.mag,
    required this.timestamp,
  });

  factory MotionData.fromJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final double x = ((m['ax'] as num?) ?? (m['x'] as num?))?.toDouble() ?? 0.0;
    final double y = ((m['ay'] as num?) ?? (m['y'] as num?))?.toDouble() ?? 0.0;
    final double z = ((m['az'] as num?) ?? (m['z'] as num?))?.toDouble() ?? 0.0;

    // Calculate magnitude if not explicitly provided by firmware
    double magnitude =
        ((m['mag'] as num?) ?? (m['magnitude'] as num?))?.toDouble() ?? 0.0;
    if (magnitude == 0.0 && (x != 0 || y != 0 || z != 0)) {
      magnitude = math.sqrt((x * x) + (y * y) + (z * z));
    }

    return MotionData(
      ax: x,
      ay: y,
      az: z,
      mag: magnitude,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'ax': ax,
        'ay': ay,
        'az': az,
        'mag': mag,
        'ts': timestamp.millisecondsSinceEpoch,
      };

  static MotionData empty() => MotionData(
        ax: 0,
        ay: 0,
        az: 0,
        mag: 0,
        timestamp: DateTime.now(),
      );
}

// ==========================================================================
//  Stress Characteristic (the big one):
//  {"index":XX.X,"cat":X,"label":"...","prob":X.XX,
//   "chronic":true/false,"motion":true/false,"cal":true/false,"bat":XX}
// ==========================================================================
class StressData {
  final double index;
  final int category; // 0=Low, 1=Moderate, 2=High
  final String label;
  final double probability;
  final bool chronic;
  final bool motionArtifact;
  final bool calibrated;
  final int battery;
  final DateTime timestamp;

  const StressData({
    required this.index,
    required this.category,
    required this.label,
    required this.probability,
    required this.chronic,
    required this.motionArtifact,
    required this.calibrated,
    required this.battery,
    required this.timestamp,
  });

  factory StressData.fromJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return StressData(
      index: (m['index'] as num?)?.toDouble() ?? -1.0,
      category: (m['cat'] as num?)?.toInt() ?? -1,
      label: m['label'] as String? ?? 'Unknown',
      probability: (m['prob'] as num?)?.toDouble() ?? 0.0,
      chronic: m['chronic'] as bool? ?? false,
      motionArtifact: m['motion'] as bool? ?? false,
      calibrated: m['cal'] as bool? ?? false,
      battery: (m['bat'] as num?)?.toInt() ?? 0,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'index': index,
        'cat': category,
        'label': label,
        'prob': probability,
        'chronic': chronic,
        'motion': motionArtifact,
        'cal': calibrated,
        'bat': battery,
        'ts': timestamp.millisecondsSinceEpoch,
      };

  static StressData empty() => StressData(
        index: -1,
        category: -1,
        label: 'Waiting',
        probability: 0,
        chronic: false,
        motionArtifact: false,
        calibrated: false,
        battery: 0,
        timestamp: DateTime.now(),
      );
}

// ==========================================================================
//  Composite snapshot — all 6 characteristics at one point in time
// ==========================================================================
class SensorSnapshot {
  final HRData hr;
  final HRVData hrv;
  final GSRData gsr;
  final TempData temp;
  final MotionData motion;
  final StressData stress;
  final DateTime timestamp;

  const SensorSnapshot({
    required this.hr,
    required this.hrv,
    required this.gsr,
    required this.temp,
    required this.motion,
    required this.stress,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'hr': hr.toMap(),
        'hrv': hrv.toMap(),
        'gsr': gsr.toMap(),
        'temp': temp.toMap(),
        'motion': motion.toMap(),
        'stress': stress.toMap(),
        'ts': timestamp.millisecondsSinceEpoch,
      };

  /// CSV header row
  static String csvHeader() => 'timestamp,bpm,hr_valid,sqi,rmssd,sdnn,pnn50,'
      'gsr_us,gsr_raw,skin_c,ambient_c,'
      'ax,ay,az,mag,'
      'stress_index,stress_cat,stress_label,stress_prob,'
      'chronic,motion_artifact,calibrated,battery';

  /// CSV data row
  String csvRow() => '${timestamp.toIso8601String()},'
      '${hr.bpm},${hr.valid},${hr.sqi.toStringAsFixed(2)},'
      '${hrv.rmssd.toStringAsFixed(1)},${hrv.sdnn.toStringAsFixed(1)},${hrv.pnn50.toStringAsFixed(1)},'
      '${gsr.microSiemens.toStringAsFixed(2)},${gsr.raw},'
      '${temp.skin.toStringAsFixed(2)},${temp.ambient.toStringAsFixed(2)},'
      '${motion.ax.toStringAsFixed(3)},${motion.ay.toStringAsFixed(3)},'
      '${motion.az.toStringAsFixed(3)},${motion.mag.toStringAsFixed(3)},'
      '${stress.index.toStringAsFixed(1)},${stress.category},${stress.label},'
      '${stress.probability.toStringAsFixed(2)},'
      '${stress.chronic},${stress.motionArtifact},${stress.calibrated},${stress.battery}';
}
