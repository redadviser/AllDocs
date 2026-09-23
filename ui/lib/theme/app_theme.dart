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

  // Calm, mostly neutral dark palette: a hint of blue in the greys, colour
  // reserved for the accent and for document types.
  static const Color _defaultBackground = Color(0xFF111418);
  static const Color _defaultBackgroundBottom = Color(0xFF111418);
  static const Color surface = Color(0xFF191D23);
  static const Color surfaceStrong = Color(0xFF21262E);
  static const Color surfaceSoft = Color(0xFF2A3039);
  static const Color border = Color(0xFF2A3038);
  static const Color primary = Color(0xFF5B8DEF);
  static const Color primarySoft = Color(0xFFAEB8C6);
  static const Color text = Color(0xFFECEFF3);
  static const Color mutedText = Color(0xFF9BA4B1);
  static const Color dimText = Color(0xFF6E7784);
  static const Color success = Color(0xFF5FBF77);
  static const Color warning = Color(0xFFE8B84A);
  static const Color premium = Color(0xFF9A7BE0);
  static const Color destructive = Color(0xFFE5534B);

  static const double radius = 14;

  // Bookshelf (albums screen), same construction as AllPhotos' shelves in
  // this app's neutral palette.
  static const Color shelfBack = Color(0xFF1A1F26);
  static const Color shelfSurface = Color(0xFF242A33);
  static const Color shelfEdge = Color(0xFF12161B);

  static Color get accent {
    if (highContrastMode.value) return Colors.white;
    return primaryColor.value ?? primary;
  }

  /// Dark backdrop, hue-matched to whatever primary color the user picked
  /// (falls back to the fixed defaults when none is set, for an exact match
  /// with the original look).
  static Color get background {
    if (highContrastMode.value) return Colors.black;
    final custom = primaryColor.value;
    if (custom == null) return _defaultBackground;
    return _darkTone(custom, saturation: 0.16, lightness: 0.075);
  }

  static Color get backgroundBottom {
    if (highContrastMode.value) return Colors.black;
    final custom = primaryColor.value;
    if (custom == null) return _defaultBackgroundBottom;
    return _darkTone(custom, saturation: 0.16, lightness: 0.075);
  }

  static Color _darkTone(
    Color seed, {
    required double saturation,
    required double lightness,
  }) {
    final hue = HSLColor.fromColor(seed).hue;
    return HSLColor.fromAHSL(1.0, hue, saturation, lightness).toColor();
  }

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        primary: accent,
        surface: highContrastMode.value ? Colors.black : surface,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: text,
        displayColor: text,
        fontFamily: 'Roboto',
      ),
      iconTheme: const IconThemeData(color: primarySoft),
      dividerTheme: DividerThemeData(
        color: border.withValues(alpha: 0.7),
        thickness: 1,
        space: 1,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        selectedColor: accent.withValues(alpha: 0.16),
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(color: text, fontSize: 13),
        secondaryLabelStyle: const TextStyle(color: text, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        showCheckmark: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          shape: shape,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size(0, 46),
          side: const BorderSide(color: border),
          shape: shape,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceStrong,
        hintStyle: const TextStyle(color: dimText),
        labelStyle: const TextStyle(color: mutedText),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: accent.withValues(alpha: 0.7)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        dragHandleColor: border,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titleTextStyle: const TextStyle(
          color: text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceSoft,
        contentTextStyle: const TextStyle(color: text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: primarySoft,
        textColor: text,
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
