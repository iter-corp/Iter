import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provides the pre-loaded [SharedPreferences] instance.
/// Must be overridden in [ProviderScope] before [runApp].
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider was not overridden');
});

/// Persists and toggles between light/dark theme across sessions.
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeModeNotifier(prefs);
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._prefs)
      : super(
          _prefs.getBool(_kKey) == true ? ThemeMode.dark : ThemeMode.light,
        );

  final SharedPreferences _prefs;
  static const _kKey = 'isDarkMode';

  void toggle() {
    state = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    _prefs.setBool(_kKey, state == ThemeMode.dark);
  }

  void setMode(ThemeMode mode) {
    state = mode;
    _prefs.setBool(_kKey, mode == ThemeMode.dark);
  }

  bool get isDark => state == ThemeMode.dark;
}
