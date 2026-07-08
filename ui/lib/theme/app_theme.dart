import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTheme {
  static final ValueNotifier<Color?> primaryColor = ValueNotifier(null);
  static final ValueNotifier<double> textScaleFactor = ValueNotifier(0.85);
  static final ValueNotifier<bool> highContrastMode = ValueNotifier(false);

  static const minTextScaleFactor = 0.7;
  static const maxTextScaleFactor = 1.0;
  static const textScaleDivisions = 4;

  static const String _primaryColorKey = 'theme.primary_color';
  static const String _textScaleFactorKey = 'theme.text_scale_factor';
  static const String _highContrastKey = 'theme.high_contrast';

  static const Color background = Color(0xFF061426);
  static const Color backgroundBottom = Color(0xFF082247);
  static const Color surface = Color(0xFF0B2546);
  static const Color surfaceStrong = Color(0xFF0F315F);
  static const Color surfaceSoft = Color(0xFF113A70);
  static const Color border = Color(0xFF1E477C);
  static const Color primary = Color(0xFF3F8DFF);
  static const Color primarySoft = Color(0xFF7DAEFF);
  static const Color text = Color(0xFFF4F7FF);
  static const Color mutedText = Color(0xFF9DAFD1);
  static const Color dimText = Color(0xFF7489B3);
  static const Color success = Color(0xFF74D76A);
  static const Color warning = Color(0xFFFFC94A);
  static const Color premium = Color(0xFF9A5DFF);
  static const Color destructive = Color(0xFFEF4444);

  static Color get accent {
    if (highContrastMode.value) return Colors.white;
    return primaryColor.value ?? primary;
  }

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: highContrastMode.value
          ? Colors.black
          : background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: highContrastMode.value ? Colors.black : surface,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: text,
        displayColor: text,
        fontFamily: 'Roboto',
      ),
      iconTheme: const IconThemeData(color: primarySoft),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        selectedColor: accent.withValues(alpha: 0.18),
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(color: mutedText),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : mutedText,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? accent : surfaceStrong,
        ),
      ),
    );
  }

  static Future<void> loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt(_primaryColorKey);
    if (colorValue != null) primaryColor.value = Color(colorValue);
    textScaleFactor.value = (prefs.getDouble(_textScaleFactorKey) ?? 0.85)
        .clamp(minTextScaleFactor, maxTextScaleFactor)
        .toDouble();
    highContrastMode.value = prefs.getBool(_highContrastKey) ?? false;
  }

  static Future<void> setPrimaryColor(Color? color) async {
    primaryColor.value = color;
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(_primaryColorKey);
    } else {
      await prefs.setInt(_primaryColorKey, color.toARGB32());
    }
  }

  static Future<void> setTextScaleFactor(double factor) async {
    final safeFactor = factor
        .clamp(minTextScaleFactor, maxTextScaleFactor)
        .toDouble();
    textScaleFactor.value = safeFactor;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_textScaleFactorKey, safeFactor);
  }

  static Future<void> setHighContrastMode(bool enabled) async {
    highContrastMode.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_highContrastKey, enabled);
  }
}
