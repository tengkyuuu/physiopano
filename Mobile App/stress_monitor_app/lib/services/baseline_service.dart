/// Baseline calibration service.
///
/// Collects 5 minutes of resting physiological data to establish
/// user-specific mean & std for z-score normalization.
///
/// Enhanced for AI migration: now tracks accelerometer magnitude
/// baseline and uses population fallback defaults matching
/// stress_model.h's baselineAddSample() logic.
library;

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'database_service.dart';
import '../models/sensor_data.dart';

class BaselineService extends ChangeNotifier {
  final DatabaseService _db;

  BaselineService(this._db);

  bool _isCalibrating = false;
  bool get isCalibrating => _isCalibrating;

  bool _isCalibrated = false;
  bool get isCalibrated => _isCalibrated;

  // Baseline values
  double hrMean = 0, hrStd = 1;
  double hrvMean = 0, hrvStd = 1; // RMSSD mean/std
  double gsrMean = 0, gsrStd = 1; // EDA mean/std
  double tempMean = 0, tempStd = 1;
  double accMagMean = 1.0, accMagStd = 0.1; // NEW: accelerometer magnitude

  // Collection buffers
  final List<double> _hrSamples = [];
  final List<double> _hrvSamples = [];
  final List<double> _gsrSamples = [];
  final List<double> _tempSamples = [];
  final List<double> _accMagSamples = []; // NEW

  /// Load saved baseline from SQLite if available.
  /// Forget the current person's baseline (sign-out / account switch).
  void reset() {
    hrMean = 0;
    hrStd = 1;
    hrvMean = 0;
    hrvStd = 1;
    gsrMean = 0;
    gsrStd = 1;
    tempMean = 0;
    tempStd = 1;
    accMagMean = 1.0;
    accMagStd = 0.1;
    _hrSamples.clear();
    _hrvSamples.clear();
    _gsrSamples.clear();
    _tempSamples.clear();
    _accMagSamples.clear();
    _isCalibrating = false;
    _isCalibrated = false;
    notifyListeners();
  }

  Future<void> loadBaseline(String userId) async {
    final data = await _db.getBaseline(userId);
    // A person without a saved baseline is uncalibrated — never inherit the
    // previous person's values on a shared phone.
    if (data == null) {
      reset();
      return;
    }
    {
      hrMean = (data['hr_mean'] as num).toDouble();
      hrStd = (data['hr_std'] as num).toDouble();
      hrvMean = (data['hrv_mean'] as num).toDouble();
      hrvStd = (data['hrv_std'] as num).toDouble();
      gsrMean = (data['gsr_mean'] as num).toDouble();
      gsrStd = (data['gsr_std'] as num).toDouble();
      tempMean = (data['temp_mean'] as num).toDouble();
      tempStd = (data['temp_std'] as num).toDouble();
      // Load accMag baseline (with fallback for old schema)
      accMagMean = (data['accmag_mean'] as num?)?.toDouble() ?? 1.0;
      accMagStd = (data['accmag_std'] as num?)?.toDouble() ?? 0.1;
      _isCalibrated = true;
      notifyListeners();
    }
  }

  /// Start collecting calibration samples.
  void startCalibration() {
    _hrSamples.clear();
    _hrvSamples.clear();
    _gsrSamples.clear();
    _tempSamples.clear();
    _accMagSamples.clear();
    _isCalibrating = true;
    _isCalibrated = false;
    notifyListeners();
  }

  /// Feed a data sample during calibration. Called from BLE on each update.
  /// Matches firmware's baselineAddSample() with conditional accumulation.
  void addSample(HRData hr, HRVData hrv, GSRData gsr, TempData temp,
      [MotionData? motion]) {
    if (!_isCalibrating) return;

    // HR — only accumulate when PPG has valid lock-on (firmware: hr > 30 && hr < 220)
    if (hr.valid && hr.bpm > 30 && hr.bpm < 220) {
      _hrSamples.add(hr.bpm.toDouble());
    }
    // RMSSD — only accumulate when HRV computation is valid (firmware: rmssd > 0 && rmssd < 500)
    if (hrv.valid && hrv.rmssd > 0 && hrv.rmssd < 500) {
      _hrvSamples.add(hrv.rmssd);
    }
    // EDA — always valid
    if (gsr.microSiemens > 0) _gsrSamples.add(gsr.microSiemens);
    // Temp — skip sentinel values (firmware: temp > 20 && temp < 45)
    if (temp.skin > 20 && temp.skin < 45) _tempSamples.add(temp.skin);
    // AccMag — skip sentinel values (firmware: accMag > 0.5 && accMag < 5)
    if (motion != null && motion.mag > 0.5 && motion.mag < 5.0) {
      _accMagSamples.add(motion.mag);
    }
  }

  /// Finalize calibration and save to SQLite.
  /// Uses population fallback defaults matching stress_model.h when
  /// insufficient valid samples are collected.
  Future<void> completeCalibration(String userId) async {
    _isCalibrating = false;

    // HR: population fallback (Thesis Table 3.1A: 60-100 bpm rest)
    if (_hrSamples.length >= 30) {
      hrMean = _mean(_hrSamples);
      hrStd = _std(_hrSamples);
    } else {
      hrMean = 75.0;
      hrStd = 10.0;
    }

    // HRV/RMSSD: population fallback (Shaffer & Ginsberg, 2017: ~30-80ms rest)
    if (_hrvSamples.length >= 10) {
      hrvMean = _mean(_hrvSamples);
      hrvStd = _std(_hrvSamples);
    } else {
      hrvMean = 50.0;
      hrvStd = 15.0;
    }

    if (_gsrSamples.length >= 10) {
      gsrMean = _mean(_gsrSamples);
      gsrStd = _std(_gsrSamples);
    } else {
      gsrMean = 2.0; // Typical resting skin conductance (µS)
      gsrStd = 0.5;
    }
    if (_tempSamples.length >= 10) {
      tempMean = _mean(_tempSamples);
      tempStd = _std(_tempSamples);
    } else {
      tempMean = 32.0; // Typical resting wrist skin temp (°C)
      tempStd = 0.5;
    }
    if (_accMagSamples.length >= 10) {
      accMagMean = _mean(_accMagSamples);
      accMagStd = _std(_accMagSamples);
    } else {
      accMagMean = 1.0; // Gravity
      accMagStd = 0.1;
    }

    // Floor stds to prevent div-by-zero in z-scoring (matching firmware)
    if (gsrStd < 0.01) gsrStd = 0.01;
    if (tempStd < 0.01) tempStd = 0.01;
    if (hrStd < 1.0) hrStd = 1.0;
    if (hrvStd < 1.0) hrvStd = 1.0;
    if (accMagStd < 0.01) accMagStd = 0.01;

    _isCalibrated = true;

    await _db.saveBaseline(
      userId: userId,
      hrMean: hrMean,
      hrStd: hrStd,
      hrvMean: hrvMean,
      hrvStd: hrvStd,
      gsrMean: gsrMean,
      gsrStd: gsrStd,
      tempMean: tempMean,
      tempStd: tempStd,
      sampleCount: _hrSamples.length,
      accMagMean: accMagMean,
      accMagStd: accMagStd,
    );

    notifyListeners();
  }

  /// Clear baseline for recalibration.
  Future<void> clearBaseline(String userId) async {
    _isCalibrated = false;
    _isCalibrating = false;
    await _db.clearBaseline(userId);
    notifyListeners();
  }

  double _mean(List<double> values) {
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _std(List<double> values) {
    final m = _mean(values);
    final variance =
        values.map((v) => (v - m) * (v - m)).reduce((a, b) => a + b) /
            values.length;
    return sqrt(variance);
  }
}
