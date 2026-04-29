import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global "preferred language" (BCP-47 code) used to translate incoming
/// content for this user. Defaults to English when nothing is set yet.
///
/// Stored in SharedPreferences under [_kPrefsKey] so the choice
/// survives app restarts and is accessible from anywhere via
/// [preferredLanguageProvider].
const String _kPrefsKey = 'app_preferred_lang';
const String kPreferredLanguageDefault = 'en';

class PreferredLanguageNotifier extends StateNotifier<String> {
  PreferredLanguageNotifier() : super(kPreferredLanguageDefault) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kPrefsKey);
    if (code != null && code.isNotEmpty) state = code;
  }

  Future<void> set(String code) async {
    if (code.isEmpty || code == state) return;
    state = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKey, code);
  }
}

final preferredLanguageProvider =
    StateNotifierProvider<PreferredLanguageNotifier, String>(
  (_) => PreferredLanguageNotifier(),
);
