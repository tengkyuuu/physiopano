import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/session.dart';

/// A service responsible for converting Session data into a CSV
/// and sharing it for external analysis (e.g., Thesis data processing).
class ExportService {
  /// Exports a session to a CSV file and opens the system Share dialog.
  static Future<void> exportSessionToCsv(Session session) async {
    if (kIsWeb) {
      throw Exception(
          'Data export is not supported on Web. Please use Android/iOS.');
    }

    try {
      final List<List<dynamic>> rows = [];

      // 1. Header Row
      rows.add([
        'Timestamp',
        'Time Offset (s)',
        'HR (bpm)',
        'HR Valid',
        'HR SQI',
        'HRV RMSSD',
        'HRV SDNN',
        'HRV pNN50',
        'GSR (uS)',
        'GSR Raw ADC',
        'Temp Skin (C)',
        'Temp Ambient (C)',
        'Motion X',
        'Motion Y',
        'Motion Z',
        'Motion Mag',
        'Stress Index',
        'Stress Category',
      ]);

      if (session.snapshots.isEmpty) {
        throw Exception('Session has no data points to export.');
      }

      final startTime = session.snapshots.first.timestamp;

      // 2. Data Rows
      for (final snap in session.snapshots) {
        final offsetSeconds =
            snap.timestamp.difference(startTime).inMilliseconds / 1000.0;

        rows.add([
          snap.timestamp.toIso8601String(),
          offsetSeconds.toStringAsFixed(3),
          snap.hr.bpm,
          snap.hr.valid ? 1 : 0,
          snap.hr.sqi.toStringAsFixed(3),
          snap.hrv.rmssd.toStringAsFixed(3),
          snap.hrv.sdnn.toStringAsFixed(3),
          snap.hrv.pnn50.toStringAsFixed(3),
          snap.gsr.microSiemens.toStringAsFixed(3),
          snap.gsr.raw,
          snap.temp.skin.toStringAsFixed(2),
          snap.temp.ambient.toStringAsFixed(2),
          snap.motion.ax.toStringAsFixed(3),
          snap.motion.ay.toStringAsFixed(3),
          snap.motion.az.toStringAsFixed(3),
          snap.motion.mag.toStringAsFixed(3),
          snap.stress.index >= 0 ? snap.stress.index.toStringAsFixed(1) : '',
          snap.stress.index >= 0 ? snap.stress.label : 'Calibrating',
        ]);
      }

      // Convert to CSV string with standard darts primitive
      final StringBuffer sb = StringBuffer();
      for (final row in rows) {
        // Enclose each cell in quotes just in case, and join by commas
        final String csvLine = row.map((cell) => '"$cell"').join(',');
        sb.writeln(csvLine);
      }
      final String csvData = sb.toString();

      // Get temporary directory
      final Directory tempDir = await getTemporaryDirectory();

      // Determine file name
      final DateFormat formatter = DateFormat('yyyyMMdd_HHmm');
      final String dateStr = formatter.format(session.startTime);
      final String fileName = 'PHYSIOPAÑO_Export_$dateStr.csv';

      final String filePath = '${tempDir.path}/$fileName';

      // Write file
      final File file = File(filePath);
      await file.writeAsString(csvData);

      // Share file using share_plus
      // ignore: deprecated_member_use
      final result = await Share.shareXFiles(
        [XFile(filePath)],
        text: 'PHYSIOPAÑO Session Data ($dateStr)',
        subject: 'Exported Thesis Session Data',
      );

      if (result.status == ShareResultStatus.success) {
        // Shared successfully
      }
    } catch (e) {
      throw Exception('Failed to export CSV: $e');
    }
  }
}
