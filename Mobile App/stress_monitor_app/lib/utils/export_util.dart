/// Export utility — saves session data to CSV or JSON and shares via
/// the system share sheet.
library;

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/session.dart';

enum ExportFormat { csv, json }

class ExportUtil {
  static final _dateFmt = DateFormat('yyyyMMdd_HHmmss');

  /// Export a session to a file and open the share sheet.
  static Future<void> exportSession(Session session, ExportFormat format) async {
    final dir = await getTemporaryDirectory();
    final timestamp = _dateFmt.format(session.startTime);
    final ext = format == ExportFormat.csv ? 'csv' : 'json';
    final filename = 'stress_session_$timestamp.$ext';
    final file = File('${dir.path}/$filename');

    final content = format == ExportFormat.csv
        ? session.toCsv()
        : session.toExportJson();

    await file.writeAsString(content);

    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'PHYSIOPAÑO Session — $timestamp',
      text: 'Session data: ${session.snapshotCount} samples, '
          'duration ${session.durationString}',
    );
  }
}
