import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/session.dart';

class PdfReportGenerator {
  static Future<void> generateAndPrintSessionReport({
    required Session session,
    required String patientName,
    required String patientId,
  }) async {
    final pdf = pw.Document(
      title: 'PHYSIOPAÑO Session Report',
      author: 'PHYSIOPAÑO Wearable System',
    );

    final font = await PdfGoogleFonts.openSansRegular();
    final fontBold = await PdfGoogleFonts.openSansBold();

    final dateFormat = DateFormat('MMMM d, yyyy - h:mm a');
    final startStr = dateFormat.format(session.startTime);
    final durationStr =
        '${session.duration.inMinutes}m ${session.duration.inSeconds % 60}s';

    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(
          base: font,
          bold: fontBold,
        ),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            _buildHeader(patientName, patientId, startStr),
            pw.SizedBox(height: 20),
            _buildSummaryBox(session, durationStr),
            pw.SizedBox(height: 20),
            _buildStressDistribution(session),
            pw.SizedBox(height: 20),
            if (session.notes != null && session.notes!.isNotEmpty)
              _buildNotesBox(session.notes!),
            pw.Spacer(),
            _buildFooter(),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Session_${session.id.length >= 8 ? session.id.substring(0, 8) : session.id}_Report.pdf',
    );
  }

  static pw.Widget _buildHeader(String name, String id, String date) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('CLINICAL SESSION REPORT',
            style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800)),
        pw.SizedBox(height: 4),
        pw.Text('PHYSIOPAÑO Wearable Physiological System',
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
        pw.Divider(color: PdfColors.blue800, thickness: 2),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Patient: ${name.isNotEmpty ? name : "N/A"}'),
                pw.Text('Subject ID: ${id.isNotEmpty ? id : "N/A"}'),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Session Date: $date'),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildSummaryBox(Session session, String duration) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        color: PdfColors.grey50,
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _summaryItem('Duration', duration),
          _summaryItem(
              'Avg HR', session.avgHeartRate >= 0
                  ? '${session.avgHeartRate.toStringAsFixed(1)} bpm'
                  : 'N/A'),
          _summaryItem('Avg Stress Index',
              '${session.avgStressIndex.toStringAsFixed(1)} / 100'),
          _summaryItem('Data Points', '${session.snapshotCount}'),
        ],
      ),
    );
  }

  static pw.Widget _summaryItem(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(label,
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        pw.Text(value,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _buildStressDistribution(Session session) {
    final dist = session.stressDistribution;
    final high = (dist['High'] ?? 0).round();
    final moderate = (dist['Moderate'] ?? 0).round();
    final low = (dist['Low'] ?? 0).round();
    final int total = high + moderate + low;
    if (total == 0) return pw.SizedBox();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Stress Level Distribution',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),

        // Simple horizontal bar chart approximation
        pw.Container(
          height: 30,
          width: double.infinity,
          decoration: pw.BoxDecoration(
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            border: pw.Border.all(color: PdfColors.grey300),
          ),
          child: pw.Row(
            children: [
              if (high > 0)
                pw.Expanded(
                  flex: high,
                  child: pw.Container(color: PdfColors.red400),
                ),
              if (moderate > 0)
                pw.Expanded(
                  flex: moderate,
                  child: pw.Container(color: PdfColors.orange400),
                ),
              if (low > 0)
                pw.Expanded(
                  flex: low,
                  child: pw.Container(color: PdfColors.green400),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            _legendItem('High', PdfColors.red400, high, total),
            _legendItem('Moderate', PdfColors.orange400, moderate, total),
            _legendItem('Low', PdfColors.green400, low, total),
          ],
        ),
      ],
    );
  }

  static pw.Widget _legendItem(
      String label, PdfColor color, int count, int total) {
    final percent =
        total > 0 ? (count / total * 100).toStringAsFixed(1) : '0.0';
    return pw.Row(
      children: [
        pw.Container(width: 12, height: 12, color: color),
        pw.SizedBox(width: 4),
        pw.Text('$label: $percent%'),
      ],
    );
  }

  static pw.Widget _buildNotesBox(String notes) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Clinical Notes / Observations',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
          ),
          child: pw.Text(notes),
        ),
      ],
    );
  }

  static pw.Widget _buildFooter() {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 4),
        pw.Text('Generated by PHYSIOPAÑO Mobile Application',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.Text(
            'This report is for informational purposes and does not constitute a medical diagnosis.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
      ],
    );
  }
}
