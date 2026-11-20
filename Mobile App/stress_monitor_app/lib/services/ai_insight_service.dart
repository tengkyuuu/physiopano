/// AI-powered stress session insight generator.
///
/// Uses Google Gemini API (FREE tier via Google AI Studio) to analyze a
/// completed session and generate a personalized 2–3 sentence insight.
///
/// Free tier limits: 15 requests/minute, 1500 requests/day — more than enough.
/// Get your free API key at: https://aistudio.google.com/app/apikey
///
/// Flow:
///   Session ends → generateInsight(session) → Gemini analyzes data
///   → insight saved to Firestore → shown in session detail screen.
library;

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/session.dart';

class AiInsightService {
  // ---------------------------------------------------------------
  // Set GEMINI_API_KEY with --dart-define for local use.
  // ---------------------------------------------------------------
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  // ---------------------------------------------------------------

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  late final GenerativeModel _model = GenerativeModel(
    model: 'gemini-1.5-flash',
    apiKey: _apiKey,
    generationConfig: GenerationConfig(
      temperature: 0.7,
      maxOutputTokens: 150,
    ),
  );

  /// Generate and save an AI insight for [session].
  /// Runs silently in background — errors are logged, not thrown.
  Future<String?> generateInsight(Session session) async {
    if (_apiKey.isEmpty) {
      debugPrint('[AI] No API key set. Get a free key at aistudio.google.com');
      return null;
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    // Need at least some stress data to analyze
    if (session.snapshotCount < 5) return null;

    try {
      final response = await _model.generateContent(
        [Content.text(_buildPrompt(session))],
      );
      final insight = response.text?.trim();

      if (insight != null && insight.isNotEmpty) {
        await _firestore
            .collection('users')
            .doc(uid)
            .collection('sessions')
            .doc(session.id)
            .set({'ai_insight': insight}, SetOptions(merge: true));
        debugPrint('[AI] Insight saved for session ${session.id}');
      }

      return insight;
    } catch (e) {
      debugPrint('[AI] Insight generation failed: $e');
      return null;
    }
  }

  /// Load a previously generated insight for [sessionId].
  Future<String?> loadInsight(String sessionId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .doc(sessionId)
          .get();
      return doc.data()?['ai_insight'] as String?;
    } catch (_) {
      return null;
    }
  }

  String _buildPrompt(Session session) {
    final durationMin = session.duration.inMinutes;
    final avgStress = session.avgStressIndex.toStringAsFixed(1);
    final avgHr = session.avgHeartRate >= 0
        ? session.avgHeartRate.toStringAsFixed(0)
        : 'N/A';
    final dist = session.stressDistribution;
    // Keys are capitalized ('Low', 'Moderate', 'High') and values are
    // already percentages (0–100), so no multiplication needed.
    final lowPct = (dist['Low'] ?? 0).toStringAsFixed(0);
    final modPct = (dist['Moderate'] ?? 0).toStringAsFixed(0);
    final highPct = (dist['High'] ?? 0).toStringAsFixed(0);
    final timeOfDay = _timeLabel(session.startTime.hour);

    return '''
You are a wellness assistant for a wearable physiological data monitor worn by a Filipino university student.
Analyze this monitoring session and give a short, empathetic, actionable insight.

Session data:
- Duration: $durationMin minutes ($timeOfDay)
- Average stress index: $avgStress / 100
- Average heart rate: $avgHr bpm
- Stress breakdown: $lowPct% low, $modPct% moderate, $highPct% high
- Samples recorded: ${session.snapshotCount}

Rules:
- Write exactly 2 sentences maximum.
- Be specific about the numbers.
- End with one practical tip for a student.
- Write in second person (Your...).
- Do NOT use bullet points or markdown.
''';
  }

  String _timeLabel(int hour) {
    if (hour < 6) return 'early morning';
    if (hour < 12) return 'morning';
    if (hour < 14) return 'midday';
    if (hour < 18) return 'afternoon';
    if (hour < 21) return 'evening';
    return 'night';
  }
}
