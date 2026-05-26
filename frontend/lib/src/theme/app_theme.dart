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
  static final ButtonStyle _primaryButtonStyle = FilledButton.styleFrom(
    backgroundColor: AppColors.purpleVivid,
    foregroundColor: Colors.white,
    disabledBackgroundColor: AppColors.purpleVivid.withValues(alpha: 0.45),
    disabledForegroundColor: Colors.white.withValues(alpha: 0.75),
    elevation: 4,
    shadowColor: AppColors.purple.withValues(alpha: 0.35),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    textStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(30),
    ),
  );

  static final ButtonStyle _outlinedButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: AppColors.purpleVivid,
    disabledForegroundColor: AppColors.purpleVivid.withValues(alpha: 0.45),
    side: const BorderSide(color: AppColors.purpleVivid, width: 1.4),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
    textStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(30),
    ),
  );

  static final ButtonStyle _textButtonStyle = TextButton.styleFrom(
    foregroundColor: AppColors.purpleVivid,
    disabledForegroundColor: AppColors.purpleVivid.withValues(alpha: 0.45),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    textStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(30),
    ),
  );
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
    elevatedButtonTheme: ElevatedButtonThemeData(style: _primaryButtonStyle),
    filledButtonTheme: FilledButtonThemeData(style: _primaryButtonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: _outlinedButtonStyle),
    textButtonTheme: TextButtonThemeData(style: _textButtonStyle),
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
    // Material 3 hides the OFF thumb against a white surface on Android
    // (default outline-colored thumb blends with light track). Pin the
    // colors so the circle is always visible regardless of state.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return const Color(0xFF6B6B70);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.purple;
        return const Color(0xFFE4E4EA);
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.purple;
        }
        return const Color(0xFFCFCFD6);
      }),
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
    elevatedButtonTheme: ElevatedButtonThemeData(style: _primaryButtonStyle),
    filledButtonTheme: FilledButtonThemeData(style: _primaryButtonStyle),
    outlinedButtonTheme: OutlinedButtonThemeData(style: _outlinedButtonStyle),
    textButtonTheme: TextButtonThemeData(style: _textButtonStyle),
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
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return const Color(0xFFB8B8C0);
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.purple;
        return const Color(0xFF3A3A40);
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.purple;
        return const Color(0xFF50505A);
      }),
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
