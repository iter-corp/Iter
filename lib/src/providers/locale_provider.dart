import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_provider.dart' show sharedPreferencesProvider;

/// The set of UI languages the app ships with.
///
/// `code` is the BCP-47 language code we persist and feed to
/// [Locale]. Kurdish Sorani uses `ckb` (Central Kurdish), the
/// ISO-639-3 code that platforms understand.
enum AppLanguage {
  english('en', 'English', 'English', TextDirection.ltr),
  arabic('ar', 'Arabic', 'العربية', TextDirection.rtl),
  kurdish('ckb', 'Kurdish (Sorani)', 'کوردیی ناوەندی', TextDirection.rtl);

  const AppLanguage(
    this.code,
    this.englishName,
    this.nativeName,
    this.direction,
  );

  final String code;
  final String englishName;
  final String nativeName;
  final TextDirection direction;

  bool get isRtl => direction == TextDirection.rtl;

  Locale get locale => Locale(code);

  static AppLanguage fromCode(String? code) {
    return AppLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguage.english,
    );
  }
}

/// Persists and exposes the active UI language across sessions.
///
/// Mirrors the design of [themeModeProvider]: backed by the same
/// pre-loaded [SharedPreferences] instance so the choice survives
/// restarts and is readable synchronously at startup.
final localeProvider =
    StateNotifierProvider<LocaleNotifier, AppLanguage>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return LocaleNotifier(prefs);
});

class LocaleNotifier extends StateNotifier<AppLanguage> {
  LocaleNotifier(this._prefs) : super(_initial(_prefs));

  final SharedPreferences _prefs;
  static const _kKey = 'app_ui_language';

  /// First launch → follow the device language when it is one we
  /// support, otherwise English. Subsequent launches → the saved
  /// choice wins.
  static AppLanguage _initial(SharedPreferences prefs) {
    final saved = prefs.getString(_kKey);
    if (saved != null && saved.isNotEmpty) {
      return AppLanguage.fromCode(saved);
    }
    final deviceCode = ui.PlatformDispatcher.instance.locale.languageCode;
    return AppLanguage.fromCode(deviceCode);
  }

  void setLanguage(AppLanguage language) {
    if (language == state) return;
    state = language;
    _prefs.setString(_kKey, language.code);
  }

  bool get isRtl => state.isRtl;
}
