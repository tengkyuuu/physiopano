import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themePrefKey = 'theme_preference';

  /// Paper is a light-first system; dark is opt-in.
  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;
  bool get isDarkMode => _mode == ThemeMode.dark;

  ThemeProvider() {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final String? themeStr = prefs.getString(_themePrefKey);
    _mode = themeStr == 'dark' ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePrefKey, _mode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }

  Future<void> setDarkMode(bool isDark) async {
    _mode = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePrefKey, isDark ? 'dark' : 'light');
    notifyListeners();
  }
}

/// Legacy palette names, resolved to the PHYSIOPAÑO "Paper" palette
/// (lib/theme/physiopano_tokens.dart, light). Screens still read these
/// constants directly; new code should use `Theme.of(context).extension<PpColors>()`.
class AppColors {
  // Backgrounds: warm paper. Cards are the same paper lifted by shadow.
  static const Color deepBlack  = Color(0xFFF4F1EA);   // ground (paper)
  static const Color surface    = Color(0xFFF3F0EA);   // raised paper
  static const Color cardDark   = Color(0xFFF3F0EA);   // raised paper (cards)
  static const Color cardDarkAlt= Color(0xFFEDEEF0);   // cool inset / info panel
  static const Color primaryGreen = Color(0xFF242A32); // ink feature card
  static const Color darkGreen  = Color(0xFF242A32);   // ink feature card
  static const Color onPanel    = Color(0xFFF4F1EA);

  // Lines (used sparingly: Paper prefers shadow to border)
  static const Color border     = Color(0xFFE2DED5);
  static const Color borderDim  = Color(0xFFEAE6DE);

  // Text
  static const Color textPrimary   = Color(0xFF242A32); // ink
  static const Color textSecondary = Color(0xFF505966); // muted
  static const Color textMuted     = Color(0xFF646D7A); // quiet labels

  // Brand: royal blue (action, selection, eyebrows)
  static const Color emerald    = Color(0xFF0758E8);
  static const Color teal       = Color(0xFF0758E8);
  static const Color accentDim  = Color(0xFF0546BA);
  static const Color onBrand    = Color(0xFFFFFFFF);
  static const Color focus      = Color(0xFF0758E8);
  static const Color brandSoft  = Color(0xFFE3ECFD);

  // Secondary hues for pictograms and illustration
  static const Color mint   = Color(0xFF2F9D7E);
  static const Color sun    = Color(0xFFC98A1B);
  static const Color lilac  = Color(0xFF6D5BD0);
  static const Color coral  = Color(0xFFD9674E);

  // Support route (stations 1-5). Always shown with number + pictogram.
  static const Color route1 = Color(0xFF2F9D7E); // self-help
  static const Color route2 = Color(0xFF0758E8); // community & peer
  static const Color route3 = Color(0xFFC98A1B); // primary care
  static const Color route4 = Color(0xFF6D5BD0); // tele-mental health
  static const Color route5 = Color(0xFF5B6678); // specialist

  // Levels: one-hue blue ramp, never red/amber/green. Pair with a word.
  static const Color levelLow   = Color(0xFFBCD0F8);
  static const Color levelMid   = Color(0xFF6E9BF0);
  static const Color levelHigh  = Color(0xFF0546BA);

  // Status
  static const Color gold       = Color(0xFFC98A1B);   // attention (not "danger")
  static const Color danger     = Color(0xFFD6453A);   // crisis: urgent-risk UI and errors only
  static const Color surfaceDim = Color(0xFFEDEEF0);

  // Gradients: flat paper, plus the one blue button sheen.
  static const LinearGradient backgroundGradient = LinearGradient(colors: [deepBlack, deepBlack]);
  static const LinearGradient cardGradient = LinearGradient(colors: [cardDark, cardDark]);
  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF2A72F0), Color(0xFF0758E8)],
  );
  static const LinearGradient accentGradient = buttonGradient;
  static const LinearGradient headerGradient = LinearGradient(colors: [primaryGreen, primaryGreen]);
}
