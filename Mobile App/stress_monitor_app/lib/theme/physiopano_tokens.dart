// PHYSIOPAÑO "Paper" design system for Flutter.
// Mirrors design-system/tokens.css (web).
//
//   MaterialApp(theme: PpTheme.light(), darkTheme: PpTheme.dark(), ...)
//
// Principles
//   1. Paper first. A warm paper ground; cards are the same paper lifted by a
//      soft shadow and a white hairline, never by grey borders.
//   2. One accent. Royal blue carries action, selection and the eyebrow labels.
//      Ink is used for text and for the single dark feature card per screen.
//   3. Editorial type. Plus Jakarta Sans, heavy headlines with tight tracking,
//      letter-spaced uppercase eyebrows, calm muted body copy.
//   4. Physical motion. Springs on touch, staggered entrances, drawn lines.
//      Celebration only for real accomplishments. Respects reduce-motion.
//
// Kept rule: route colours always travel with a station number + pictogram;
// crisis red is reserved for urgent-risk UI.

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:google_fonts/google_fonts.dart';

/// The stepped support ladder. Order is meaningful.
enum PpStation { selfHelp, community, primaryCare, teleMH, specialist }

/// Secondary hues for sensor pictograms and illustration. Muted so they sit on
/// paper next to the blue accent without competing with it.
class PpAccent {
  static const sky = Color(0xFF0758E8); // = brand
  static const mint = Color(0xFF2F9D7E);
  static const sun = Color(0xFFC98A1B);
  static const lilac = Color(0xFF6D5BD0);
  static const coral = Color(0xFFD9674E);

  /// Confetti/celebration palette: brand-led, with paper-friendly companions.
  static const all = [sky, Color(0xFF7FA6F5), mint, sun, Color(0xFF242A32)];
}

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
    required this.inkQuiet,
    required this.line,
    required this.focus,
    required this.brand,
    required this.brandSoft,
    required this.onBrand,
    required this.glow,
    required this.highlight,
    required this.shade,
    required this.routes,
    required this.crisis,
  });

  final Color ground, surface, surfaceSunk, panel, onPanel, ink, inkMuted, inkQuiet, line, focus;
  final Color brand, brandSoft, onBrand, glow, crisis;

  /// Top-left light and bottom-right shadow of raised paper.
  final Color highlight, shade;
  final Map<PpStation, Color> routes;

  Color route(PpStation s) => routes[s]!;

  /// Text colour that passes AA on a route fill.
  Color onRoute(PpStation s) => s == PpStation.primaryCare ? const Color(0xFF242A32) : Colors.white;

  static const light = PpColors(
    ground: Color(0xFFF4F1EA),
    surface: Color(0xFFF3F0EA),
    surfaceSunk: Color(0xFFEDEEF0),
    panel: Color(0xFF242A32),
    onPanel: Color(0xFFF4F1EA),
    ink: Color(0xFF242A32),
    inkMuted: Color(0xFF505966),
    inkQuiet: Color(0xFF646D7A),
    line: Color(0xFFE2DED5),
    focus: Color(0xFF0758E8),
    brand: Color(0xFF0758E8),
    brandSoft: Color(0xFFE3ECFD),
    onBrand: Colors.white,
    glow: Color(0x730758E8),
    highlight: Color(0xD9FFFFFF),
    shade: Color(0x29242A32),
    crisis: Color(0xFFD6453A),
    routes: {
      PpStation.selfHelp: PpAccent.mint,
      PpStation.community: Color(0xFF0758E8),
      PpStation.primaryCare: PpAccent.sun,
      PpStation.teleMH: PpAccent.lilac,
      PpStation.specialist: Color(0xFF5B6678),
    },
  );

  static const dark = PpColors(
    ground: Color(0xFF16191E),
    surface: Color(0xFF1D2128),
    surfaceSunk: Color(0xFF14171B),
    panel: Color(0xFF0F1216),
    onPanel: Color(0xFFF1EEE7),
    ink: Color(0xFFF1EEE7),
    inkMuted: Color(0xFFA4ABB6),
    inkQuiet: Color(0xFF8A92A0),
    line: Color(0xFF2B3039),
    focus: Color(0xFF4C8DFF),
    brand: Color(0xFF4C8DFF),
    brandSoft: Color(0xFF1B2A47),
    onBrand: Colors.white,
    glow: Color(0x664C8DFF),
    highlight: Color(0x0DFFFFFF),
    shade: Color(0x99000000),
    crisis: Color(0xFFEF6A57),
    routes: {
      PpStation.selfHelp: Color(0xFF5FC4A5),
      PpStation.community: Color(0xFF4C8DFF),
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
  static const gutter = 24.0;
}

class PpRadius {
  static const control = 18.0, panel = 28.0, sheet = 36.0, pill = 999.0;
}

/// Raised / inset paper. Use these instead of borders.
class PpShadow {
  static List<BoxShadow> raised(PpColors c, {double lift = 1}) => [
        BoxShadow(color: c.shade.withValues(alpha: c.shade.a * 0.55), blurRadius: 34 * lift, spreadRadius: -12, offset: Offset(0, 14 * lift)),
        BoxShadow(color: c.shade.withValues(alpha: c.shade.a * 0.2), blurRadius: 6, offset: const Offset(0, 2)),
        BoxShadow(color: c.highlight, blurRadius: 12, offset: const Offset(-4, -4)),
      ];

  static List<BoxShadow> brand(PpColors c) => [
        BoxShadow(color: c.glow, blurRadius: 24, spreadRadius: -8, offset: const Offset(0, 12)),
      ];

  static Border edge(PpColors c) => Border.all(color: c.highlight, width: 1.5);
}

class PpMotion {
  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 520);
  static const entrance = Duration(milliseconds: 680);

  /// Expo-out. Default for entrances and layout changes.
  static const ease = Cubic(0.16, 1, 0.3, 1);

  /// Slight overshoot for things that "land".
  static const settle = Cubic(0.34, 1.4, 0.64, 1);

  /// Touch springs: snappy for buttons, soft for big surfaces.
  static const snappy = SpringDescription(mass: 1, stiffness: 520, damping: 24);
  static const soft = SpringDescription(mass: 1, stiffness: 180, damping: 18);

  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Line form carries state, not hue.
enum PpLineState { live, pending, stale }

class PpTheme {
  static ThemeData light() => _build(PpColors.light, Brightness.light);
  static ThemeData dark() => _build(PpColors.dark, Brightness.dark);

  static TextStyle font({double? size, FontWeight? weight, Color? color, double? height, double? spacing}) =>
      GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);

  /// Uppercase, letter-spaced label that sits above headlines.
  static TextStyle eyebrow(BuildContext context, {Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 12 * 0.16,
        height: 16 / 12,
        color: color ?? Theme.of(context).extension<PpColors>()!.brand,
      );

  static TextTheme _text(Color ink, Color muted) {
    final base = GoogleFonts.plusJakartaSansTextTheme();
    TextStyle s(double size, double h, FontWeight w, {double ls = 0, Color? c}) =>
        GoogleFonts.plusJakartaSans(fontSize: size, height: h / size, fontWeight: w, letterSpacing: ls * size, color: c ?? ink);
    return base.copyWith(
      displayLarge: s(56, 58, FontWeight.w800, ls: -0.045),
      displayMedium: s(44, 46, FontWeight.w800, ls: -0.042),
      displaySmall: s(36, 38, FontWeight.w800, ls: -0.04),
      headlineLarge: s(34, 36, FontWeight.w800, ls: -0.04),
      headlineMedium: s(30, 33, FontWeight.w800, ls: -0.036),
      headlineSmall: s(24, 28, FontWeight.w800, ls: -0.03),
      titleLarge: s(21, 26, FontWeight.w700, ls: -0.02),
      titleMedium: s(17, 23, FontWeight.w700, ls: -0.01),
      titleSmall: s(15, 20, FontWeight.w700),
      bodyLarge: s(17, 26, FontWeight.w400, c: muted),
      bodyMedium: s(15, 22, FontWeight.w400),
      bodySmall: s(13, 19, FontWeight.w400, c: muted),
      labelLarge: s(15, 20, FontWeight.w600),
      labelMedium: s(13, 16, FontWeight.w500, c: muted),
      labelSmall: s(11.5, 14, FontWeight.w600, ls: 0.14, c: muted),
    );
  }

  /// Sensor readings and IDs.
  static TextStyle data(BuildContext context, {double size = 16}) => GoogleFonts.plusJakartaSans(
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.03 * size,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: Theme.of(context).extension<PpColors>()!.ink,
      );

  static ThemeData _build(PpColors c, Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: c.brand,
      onPrimary: c.onBrand,
      primaryContainer: c.brandSoft,
      onPrimaryContainer: c.brand,
      secondary: c.ink,
      onSecondary: c.ground,
      tertiary: PpAccent.mint,
      onTertiary: Colors.white,
      error: c.crisis,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMuted,
      surfaceContainerHighest: c.surfaceSunk,
      surfaceContainerHigh: c.surfaceSunk,
      surfaceContainer: c.surface,
      surfaceContainerLow: c.ground,
      outline: c.line,
      outlineVariant: c.line,
    );
    const pill = StadiumBorder();
    final label = GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 16);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.ground,
      canvasColor: c.ground,
      textTheme: _text(c.ink, c.inkMuted),
      extensions: [c],
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: PpPageTransitions(),
        TargetPlatform.iOS: PpPageTransitions(),
        TargetPlatform.windows: PpPageTransitions(),
        TargetPlatform.macOS: PpPageTransitions(),
        TargetPlatform.linux: PpPageTransitions(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: c.ground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.ink,
        iconTheme: IconThemeData(color: c.ink),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: c.ink, letterSpacing: -0.5),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: c.shade.withValues(alpha: 0.35),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PpRadius.panel),
          side: BorderSide(color: c.highlight, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: c.onBrand,
          minimumSize: const Size(56, 54),
          padding: const EdgeInsets.symmetric(horizontal: 26),
          shape: pill,
          elevation: 0,
          textStyle: label,
        ).copyWith(
          shadowColor: WidgetStatePropertyAll(c.glow),
          elevation: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? 0 : 8),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: c.onBrand,
          shadowColor: c.glow,
          elevation: 8,
          minimumSize: const Size(56, 54),
          padding: const EdgeInsets.symmetric(horizontal: 26),
          shape: pill,
          textStyle: label,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(56, 54),
          foregroundColor: c.ink,
          backgroundColor: c.surface,
          side: BorderSide(color: c.highlight, width: 1.5),
          shape: pill,
          textStyle: label,
        ).copyWith(
          elevation: const WidgetStatePropertyAll(4),
          shadowColor: WidgetStatePropertyAll(c.shade.withValues(alpha: 0.25)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.brand,
          minimumSize: const Size(PpSpace.touch, PpSpace.touch),
          shape: pill,
          textStyle: label,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: c.ink)),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.brand,
        foregroundColor: c.onBrand,
        elevation: 8,
        shape: pill,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceSunk,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        hintStyle: GoogleFonts.plusJakartaSans(color: c.inkQuiet, fontSize: 16),
        labelStyle: GoogleFonts.plusJakartaSans(color: c.inkQuiet),
        floatingLabelStyle: GoogleFonts.plusJakartaSans(color: c.brand, fontWeight: FontWeight.w600),
        prefixIconColor: c.inkQuiet,
        suffixIconColor: c.inkQuiet,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(PpRadius.control), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(PpRadius.control), borderSide: BorderSide(color: c.line, width: 1)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(PpRadius.control), borderSide: BorderSide(color: c.brand, width: 1.6)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.brand,
        secondarySelectedColor: c.brand,
        checkmarkColor: c.onBrand,
        side: BorderSide(color: c.highlight, width: 1.5),
        shape: pill,
        elevation: 3,
        shadowColor: c.shade.withValues(alpha: 0.3),
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500, color: c.inkMuted),
        secondaryLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: c.onBrand),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.surface,
        selectedItemColor: c.brand,
        unselectedItemColor: c.inkQuiet,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.panel,
        contentTextStyle: GoogleFonts.plusJakartaSans(color: c.onPanel, fontSize: 14, fontWeight: FontWeight.w500),
        actionTextColor: const Color(0xFF8FB2FA),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PpRadius.control)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.ground,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.line,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(PpRadius.sheet))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.ground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PpRadius.panel)),
        titleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, color: c.ink, letterSpacing: -0.6),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : c.inkQuiet),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.brand : c.surfaceSunk),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.brand : c.line),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.brand,
        inactiveTrackColor: c.surfaceSunk,
        thumbColor: c.brand,
        overlayColor: c.brand.withValues(alpha: 0.12),
        trackHeight: 6,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.brand,
        linearTrackColor: c.surfaceSunk,
        circularTrackColor: c.surfaceSunk,
        linearMinHeight: 6,
        borderRadius: BorderRadius.circular(PpRadius.pill),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.surfaceSunk,
        height: 72,
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1),
      listTileTheme: ListTileThemeData(
        iconColor: c.inkQuiet,
        titleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
        subtitleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 13.5, color: c.inkMuted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PpRadius.control)),
      ),
    );
  }
}

/// Global page transition: the incoming page rises and fades in on an expo
/// curve while the outgoing page recedes slightly.
class PpPageTransitions extends PageTransitionsBuilder {
  const PpPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final inCurve = CurvedAnimation(parent: animation, curve: PpMotion.ease, reverseCurve: Curves.easeInCubic);
    final outCurve = CurvedAnimation(parent: secondaryAnimation, curve: PpMotion.ease);
    return AnimatedBuilder(
      animation: Listenable.merge([inCurve, outCurve]),
      child: child,
      builder: (context, child) {
        final t = inCurve.value;
        final o = outCurve.value;
        return Opacity(
          opacity: (t.clamp(0.0, 1.0) * (1 - 0.3 * o)).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 28),
            child: Transform.scale(scale: (0.97 + 0.03 * t) * (1 - 0.03 * o), child: child),
          ),
        );
      },
    );
  }
}
