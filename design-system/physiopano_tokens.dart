// PHYSIOPAÑO Wayfinding tokens for Flutter. Generated from design-system/tokens.json.
// Copy to: Mobile App/stress_monitor_app/lib/theme/physiopano_tokens.dart
// Requires: google_fonts (add `google_fonts: ^6.2.1` to pubspec.yaml).
//
//   MaterialApp(theme: PpTheme.light(), darkTheme: PpTheme.dark(), ...)
//
// Rule: route colours always travel with a station number + pictogram. Never colour alone.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The stepped support ladder. Order is meaningful.
enum PpStation { selfHelp, community, primaryCare, teleMH, specialist }

@immutable
class PpColors extends ThemeExtension<PpColors> {
  const PpColors({
    required this.ground,
    required this.surface,
    required this.surfaceSunk,
    required this.panel,
    required this.onPanel,
    required this.ink,
    required this.inkMuted,
    required this.line,
    required this.focus,
    required this.brand,
    required this.routes,
    required this.crisis,
  });

  final Color ground, surface, surfaceSunk, panel, onPanel, ink, inkMuted, line, focus, brand, crisis;
  final Map<PpStation, Color> routes;

  Color route(PpStation s) => routes[s]!;

  /// Text colour that passes AA on a route fill.
  /// Light theme: white on every route except primaryCare (gold). Dark theme routes are light, so dark text.
  Color onRoute(PpStation s) => (s == PpStation.primaryCare || ink.computeLuminance() > 0.5)
      ? const Color(0xFF10201F)
      : Colors.white;

  static const light = PpColors(
    ground: Color(0xFFEEF0EC),
    surface: Color(0xFFFBFBF8),
    surfaceSunk: Color(0xFFE3E7E2),
    panel: Color(0xFF0E2A2B),
    onPanel: Color(0xFFF3F6F2),
    ink: Color(0xFF10201F),
    inkMuted: Color(0xFF4A5A58),
    line: Color(0xFFC9D0CC),
    focus: Color(0xFF1F6FB2),
    brand: Color(0xFF0F7A68),
    crisis: Color(0xFFC63B2B),
    routes: {
      PpStation.selfHelp: Color(0xFF0F7A68),
      PpStation.community: Color(0xFF1F6FB2),
      PpStation.primaryCare: Color(0xFFB07D0F),
      PpStation.teleMH: Color(0xFF5D4BA6),
      PpStation.specialist: Color(0xFF34495E),
    },
  );

  static const dark = PpColors(
    ground: Color(0xFF0B1A1B),
    surface: Color(0xFF12292A),
    surfaceSunk: Color(0xFF081314),
    panel: Color(0xFF071415),
    onPanel: Color(0xFFF3F6F2),
    ink: Color(0xFFE8EDEA),
    inkMuted: Color(0xFFA3B3B0),
    line: Color(0xFF2A403F),
    focus: Color(0xFF5FA4E0),
    brand: Color(0xFF3FB59D),
    crisis: Color(0xFFEF6A57),
    routes: {
      PpStation.selfHelp: Color(0xFF3FB59D),
      PpStation.community: Color(0xFF5FA4E0),
      PpStation.primaryCare: Color(0xFFE3B04B),
      PpStation.teleMH: Color(0xFF9C8BE6),
      PpStation.specialist: Color(0xFF8FA6BA),
    },
  );

  @override
  PpColors copyWith() => this;

  @override
  PpColors lerp(ThemeExtension<PpColors>? other, double t) => t < 0.5 ? this : (other as PpColors);
}

class PpSpace {
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 24.0, s6 = 32.0, s7 = 48.0, s8 = 64.0;
  static const touch = 48.0;
}

class PpRadius {
  static const control = 6.0, panel = 12.0, sheet = 20.0;
}

class PpMotion {
  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 360);
  static const ease = Cubic(0.16, 1, 0.3, 1);
}

/// Line form carries state, not hue.
enum PpLineState { live, pending, stale }

class PpTheme {
  static ThemeData light() => _build(PpColors.light, Brightness.light);
  static ThemeData dark() => _build(PpColors.dark, Brightness.dark);

  static TextTheme _text(Color ink, Color muted) {
    final base = GoogleFonts.overpassTextTheme();
    TextStyle s(double size, double h, FontWeight w, {double ls = 0, Color? c}) =>
        GoogleFonts.overpass(fontSize: size, height: h / size, fontWeight: w, letterSpacing: ls * size, color: c ?? ink);
    return base.copyWith(
      displayLarge: s(64, 64, FontWeight.w800, ls: -0.03),
      displayMedium: s(44, 46, FontWeight.w800, ls: -0.02),
      headlineMedium: s(32, 36, FontWeight.w800, ls: -0.01),
      titleLarge: s(24, 30, FontWeight.w700),
      titleMedium: s(20, 28, FontWeight.w600),
      bodyLarge: s(16, 24, FontWeight.w400),
      bodyMedium: s(14, 20, FontWeight.w400, c: muted),
      labelSmall: s(12, 16, FontWeight.w600, ls: 0.06, c: muted),
      labelLarge: s(16, 20, FontWeight.w700),
    );
  }

  /// Sensor readings and IDs only.
  static TextStyle data(BuildContext context, {double size = 16}) => GoogleFonts.overpassMono(
        fontSize: size,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: Theme.of(context).extension<PpColors>()!.ink,
      );

  static ThemeData _build(PpColors c, Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: c.brand,
      onPrimary: b == Brightness.light ? Colors.white : const Color(0xFF0B1A1B),
      secondary: c.panel,
      onSecondary: c.onPanel,
      error: c.crisis,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.ink,
      surfaceContainerHighest: c.surfaceSunk,
      outline: c.line,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.ground,
      textTheme: _text(c.ink, c.inkMuted),
      extensions: [c],
      appBarTheme: AppBarTheme(
        backgroundColor: c.ground,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PpRadius.panel),
          side: BorderSide(color: c.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(PpSpace.touch, PpSpace.touch),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PpRadius.control)),
          textStyle: GoogleFonts.overpass(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(PpSpace.touch, PpSpace.touch),
          foregroundColor: c.ink,
          side: BorderSide(color: c.ink, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PpRadius.control)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(PpRadius.control), borderSide: BorderSide(color: c.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(PpRadius.control), borderSide: BorderSide(color: c.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(PpRadius.control), borderSide: BorderSide(color: c.focus, width: 2)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.brand.withValues(alpha: 0.14),
        height: 68,
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1),
    );
  }
}
