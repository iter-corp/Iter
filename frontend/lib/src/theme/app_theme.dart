import 'package:flutter/material.dart';

/// Brand colors shared across both themes.
class AppColors {
  static const purple = Color(0xFFB05ECC);
  static const purpleBright = Color(0xFFCE5DE5);
  static const purpleDeep = Color(0xFF8A3FB8);
  static const purpleVivid = Color(0xFF7E3BE8);
  static const green = Color(0xFF3BD671);
  static const red = Color(0xFFE04E5C);
  static const orange = Color(0xFFD27B2B);
}

class AppTheme {
  // ─── Light Theme ────────────────────────────────────────────
  static ThemeData light = ThemeData(
    brightness: Brightness.light,
    useMaterial3: true,
    fontFamily: null, // system default
    colorScheme: const ColorScheme.light(
      primary: AppColors.purple,
      secondary: AppColors.purpleBright,
      surface: Colors.white,
      error: AppColors.red,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Color(0xFF0F0F10),
      onError: Colors.white,
      outline: Color(0xFFEDEDF2),
      surfaceContainerHighest: Color(0xFFF0F0F0),
    ),
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerColor: const Color(0xFFEDEDF2),
    cardColor: Colors.white,
    canvasColor: const Color(0xFFF7F6FB),
    hintColor: const Color(0xFFAAAAAA),
    iconTheme: const IconThemeData(color: Color(0xFF6B6B70)),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: AppColors.purple,
      unselectedItemColor: Color(0xFF6B6B70),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.purpleBright,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        elevation: 0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF0F0F0),
      hintStyle: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );

  // ─── Dark Theme ─────────────────────────────────────────────
  static ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: null,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.purple,
      secondary: AppColors.purpleBright,
      surface: Color(0xFF1A1A1E),
      error: AppColors.red,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Color(0xFFE8E8EE),
      onError: Colors.white,
      outline: Color(0xFF2E2E34),
      surfaceContainerHighest: Color(0xFF252528),
    ),
    scaffoldBackgroundColor: const Color(0xFF111114),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1A1A1E),
      foregroundColor: Color(0xFFE8E8EE),
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerColor: const Color(0xFF2E2E34),
    cardColor: const Color(0xFF1A1A1E),
    canvasColor: const Color(0xFF151518),
    hintColor: const Color(0xFF6B6B70),
    iconTheme: const IconThemeData(color: Color(0xFF9B9BA0)),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1A1A1E),
      selectedItemColor: AppColors.purpleBright,
      unselectedItemColor: Color(0xFF6B6B70),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.purpleBright,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        elevation: 0,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF252528),
      hintStyle: const TextStyle(color: Color(0xFF6B6B70), fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}

/// Extension on BuildContext for quick theme access.
extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  // Common semantic colors
  Color get surfaceSoft => isDark ? const Color(0xFF151518) : const Color(0xFFF7F6FB);
  Color get inputFill => isDark ? const Color(0xFF252528) : const Color(0xFFF0F0F0);
  Color get cardBg => isDark ? const Color(0xFF1A1A1E) : Colors.white;
  Color get borderColor => isDark ? const Color(0xFF2E2E34) : const Color(0xFFEDEDF2);
  Color get textPrimary => isDark ? const Color(0xFFE8E8EE) : const Color(0xFF0F0F10);
  Color get textSecondary => isDark ? const Color(0xFF9B9BA0) : const Color(0xFF6B6B70);
  Color get textMuted => isDark ? const Color(0xFF6B6B70) : const Color(0xFFAAAAAA);
  Color get purpleSoft => isDark ? const Color(0xFF2D1F3D) : const Color(0xFFF5E8FA);
  Color get tagBg => isDark ? const Color(0xFF3D2E1A) : const Color(0xFFFFF2E3);
}
