import 'dart:async';
import 'dart:convert';
<<<<<<< Updated upstream

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Translation via Google Gemini.
/// We ask Gemini to translate text, instructing it to return only the
/// translated text with no explanation or prefix.
class TranslateService {
  const TranslateService();

  static const _model = 'gemini-2.5-flash';
  static const _host = 'generativelanguage.googleapis.com';
=======
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tag prefix used by every debug print emitted by [TranslateService].
/// Search the device log with: `flutter logs | grep [translate]`
const String _kTranslateLogTag = '[translate]';

void _tlog(String msg) {
  if (kDebugMode) debugPrint('$_kTranslateLogTag $msg');
}

/// Metadata for a translation target language.
///
/// [code] is the BCP-47 / Azure language code passed to
/// [TranslateService.translateText]. [label] is the human-readable name
/// shown in pickers. [stt] is the speech-to-text locale (`xx_YY` form) for
/// the in-app live translator's mic input — `null` means the device default
/// is used and live transcription may be less accurate. [rtl] is true for
/// right-to-left scripts so UI text alignment can flip.
class TranslateLanguage {
  final String code;
  final String label;
  final String? stt;
  final bool rtl;
  const TranslateLanguage(this.code, this.label, {this.stt, this.rtl = false});
}

/// Single source of truth for every language picker in the app: chat
/// auto-translate dropdown, comment translate sheet, post-caption translate
/// sheet, and the dedicated translate screen. Edit here once — every picker
/// updates automatically.
const List<TranslateLanguage> kTranslateLanguages = [
  TranslateLanguage('en', 'English (USA)', stt: 'en_US'),
  TranslateLanguage('en', 'English (UK)', stt: 'en_GB'),
  TranslateLanguage('ar', 'Arabic', stt: 'ar_SA', rtl: true),
  TranslateLanguage('ckb', 'Kurdish (Sorani)', stt: 'ar_IQ', rtl: true),
  TranslateLanguage('kmr', 'Kurdish (Kurmanji)', stt: 'tr_TR'),
  TranslateLanguage('fa', 'Persian', stt: 'fa_IR', rtl: true),
  TranslateLanguage('tr', 'Turkish', stt: 'tr_TR'),
  TranslateLanguage('es', 'Spanish', stt: 'es_ES'),
  TranslateLanguage('fr', 'French', stt: 'fr_FR'),
  TranslateLanguage('de', 'German', stt: 'de_DE'),
  TranslateLanguage('it', 'Italian', stt: 'it_IT'),
  TranslateLanguage('pt-BR', 'Portuguese (Brazil)', stt: 'pt_BR'),
  TranslateLanguage('pt-PT', 'Portuguese (Portugal)', stt: 'pt_PT'),
  TranslateLanguage('ru', 'Russian', stt: 'ru_RU'),
  TranslateLanguage('uk', 'Ukrainian', stt: 'uk_UA'),
  TranslateLanguage('pl', 'Polish', stt: 'pl_PL'),
  TranslateLanguage('nl', 'Dutch', stt: 'nl_NL'),
  TranslateLanguage('sv', 'Swedish', stt: 'sv_SE'),
  TranslateLanguage('no', 'Norwegian', stt: 'nb_NO'),
  TranslateLanguage('da', 'Danish', stt: 'da_DK'),
  TranslateLanguage('fi', 'Finnish', stt: 'fi_FI'),
  TranslateLanguage('cs', 'Czech', stt: 'cs_CZ'),
  TranslateLanguage('el', 'Greek', stt: 'el_GR'),
  TranslateLanguage('he', 'Hebrew', stt: 'he_IL', rtl: true),
  TranslateLanguage('ur', 'Urdu', stt: 'ur_PK', rtl: true),
  TranslateLanguage('hi', 'Hindi', stt: 'hi_IN'),
  TranslateLanguage('bn', 'Bengali', stt: 'bn_IN'),
  TranslateLanguage('ta', 'Tamil', stt: 'ta_IN'),
  TranslateLanguage('te', 'Telugu', stt: 'te_IN'),
  TranslateLanguage('ms', 'Malay', stt: 'ms_MY'),
  TranslateLanguage('id', 'Indonesian', stt: 'id_ID'),
  TranslateLanguage('th', 'Thai', stt: 'th_TH'),
  TranslateLanguage('vi', 'Vietnamese', stt: 'vi_VN'),
  TranslateLanguage('ja', 'Japanese', stt: 'ja_JP'),
  TranslateLanguage('ko', 'Korean', stt: 'ko_KR'),
  TranslateLanguage('zh-CN', 'Chinese (Simplified)', stt: 'zh_CN'),
  TranslateLanguage('zh-TW', 'Chinese (Traditional)', stt: 'zh_TW'),
  TranslateLanguage('sw', 'Swahili', stt: 'sw_KE'),
  TranslateLanguage('am', 'Amharic', stt: 'am_ET'),
  TranslateLanguage('so', 'Somali'),
  TranslateLanguage('ha', 'Hausa'),
  TranslateLanguage('zu', 'Zulu', stt: 'zu_ZA'),
  TranslateLanguage('af', 'Afrikaans', stt: 'af_ZA'),
  TranslateLanguage('hu', 'Hungarian', stt: 'hu_HU'),
  TranslateLanguage('ro', 'Romanian', stt: 'ro_RO'),
  TranslateLanguage('bg', 'Bulgarian', stt: 'bg_BG'),
  TranslateLanguage('sr', 'Serbian', stt: 'sr_RS'),
  TranslateLanguage('hr', 'Croatian', stt: 'hr_HR'),
  TranslateLanguage('sk', 'Slovak', stt: 'sk_SK'),
  TranslateLanguage('sl', 'Slovenian', stt: 'sl_SI'),
  TranslateLanguage('lt', 'Lithuanian', stt: 'lt_LT'),
  TranslateLanguage('lv', 'Latvian', stt: 'lv_LV'),
  TranslateLanguage('et', 'Estonian', stt: 'et_EE'),
  TranslateLanguage('is', 'Icelandic', stt: 'is_IS'),
  TranslateLanguage('ca', 'Catalan', stt: 'ca_ES'),
  TranslateLanguage('eu', 'Basque', stt: 'eu_ES'),
  TranslateLanguage('gl', 'Galician', stt: 'gl_ES'),
  TranslateLanguage('cy', 'Welsh'),
  TranslateLanguage('ga', 'Irish'),
  TranslateLanguage('sq', 'Albanian'),
  TranslateLanguage('hy', 'Armenian'),
  TranslateLanguage('az', 'Azerbaijani'),
  TranslateLanguage('ka', 'Georgian'),
  TranslateLanguage('kk', 'Kazakh'),
  TranslateLanguage('uz', 'Uzbek'),
  TranslateLanguage('mn', 'Mongolian'),
  TranslateLanguage('km', 'Khmer'),
  TranslateLanguage('lo', 'Lao'),
  TranslateLanguage('my', 'Burmese'),
  TranslateLanguage('fil', 'Filipino', stt: 'fil_PH'),
  TranslateLanguage('ne', 'Nepali'),
  TranslateLanguage('si', 'Sinhala'),
  TranslateLanguage('ps', 'Pashto', rtl: true),
  TranslateLanguage('mt', 'Maltese'),
  TranslateLanguage('eo', 'Esperanto'),
];

/// Client-side translation with provider routing.
///
/// Provider priority:
///  - Kurdish involved (source or target) → Microsoft Azure Translator only
///  - All other languages → Gemini first, then Langbly / MyMemory / FreeAPITools
///
/// Kurdish codes: ku, ckb (Sorani), kmr (Kurmanji) and any subtag variants.
class TranslateService {
  const TranslateService();

  // Round-robin index — shared across all instances for the app lifetime.
  static int _providerIndex = 0;

  // ──────────────────────────────────────────────
  // On-device translation cache
  // ──────────────────────────────────────────────
  // Stored as a single JSON map under [_kCachePrefsKey] in SharedPreferences.
  // Key format: "<srcLang>|<tgtLang>|<sha1HexOfText>" → translated text.
  // First lookup loads it once into the in-memory map; subsequent calls hit
  // memory only. We re-write the whole blob on each store — fine for the
  // expected size (capped at [_kCacheMaxEntries]) and avoids needing two
  // round-trips per write. On overflow we drop the entire cache; tracking
  // LRU per-entry would double every write for marginal benefit.
  static const String _kCachePrefsKey = 'translate_cache_v1';
  static const int _kCacheMaxEntries = 1000;
  static Map<String, String>? _cache;
  static Future<void>? _cacheLoadFuture;

  static String _cacheKey({
    required String sourceLang,
    required String targetLang,
    required String text,
  }) {
    final hash = sha1.convert(utf8.encode(text)).toString();
    return '${sourceLang.toLowerCase()}|${targetLang.toLowerCase()}|$hash';
  }

  static Future<void> _ensureCacheLoaded() {
    if (_cache != null) return Future.value();
    return _cacheLoadFuture ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_kCachePrefsKey);
        if (raw == null || raw.isEmpty) {
          _cache = <String, String>{};
        } else {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            _cache = decoded.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            );
          } else {
            _cache = <String, String>{};
          }
        }
        _tlog('cache loaded entries=${_cache!.length}');
      } catch (e) {
        _tlog('cache load FAILED: $e — starting empty');
        _cache = <String, String>{};
      }
    }();
  }

  static Future<String?> _cacheLookup({
    required String sourceLang,
    required String targetLang,
    required String text,
  }) async {
    await _ensureCacheLoaded();
    final hit = _cache![_cacheKey(
      sourceLang: sourceLang,
      targetLang: targetLang,
      text: text,
    )];
    if (hit != null) {
      _tlog('cache HIT len=${hit.length}');
    }
    return hit;
  }

  static Future<void> _cacheStore({
    required String sourceLang,
    required String targetLang,
    required String text,
    required String result,
  }) async {
    await _ensureCacheLoaded();
    final cache = _cache!;
    if (cache.length >= _kCacheMaxEntries) {
      _tlog('cache full (${cache.length}) — clearing');
      cache.clear();
    }
    cache[_cacheKey(
      sourceLang: sourceLang,
      targetLang: targetLang,
      text: text,
    )] = result;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCachePrefsKey, jsonEncode(cache));
    } catch (e) {
      _tlog('cache persist FAILED: $e');
    }
  }

  /// Clears all cached translations (memory + disk). Useful for a settings
  /// "Clear translation cache" action.
  static Future<void> clearCache() async {
    _cache = <String, String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kCachePrefsKey);
    } catch (_) {}
  }

  static bool _isKurdish(String lang) {
    final l = lang.toLowerCase();
    return l == 'ku' ||
        l.startsWith('ku-') ||
        l == 'ckb' ||
        l.startsWith('ckb-') ||
        l == 'kmr' ||
        l.startsWith('kmr-');
  }

  static bool _looksLikeKurdishText(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    // Sorani-only or strongly Kurdish-Arabic letters.
    final soraniPattern = RegExp(r'[ەۆڕڵڎڤێ]');
    if (soraniPattern.hasMatch(normalized)) {
      return true;
    }

    // Kurmanji latin letters with diacritics.
    final kurmanjiPattern = RegExp(r'[çêîşû]');
    if (kurmanjiPattern.hasMatch(normalized)) {
      return true;
    }

    return false;
  }

  static String _effectiveSourceLang({
    required String sourceLang,
    required String text,
  }) {
    if (sourceLang.toLowerCase() != 'auto') {
      return sourceLang;
    }

    // If source is auto but the text clearly looks Kurdish, force ckb.
    // This avoids Arabic mis-detection in third-party APIs.
    if (_looksLikeKurdishText(text)) {
      return 'ckb';
    }

    return sourceLang;
  }

  // ──────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────

  static String userFriendlyErrorMessage(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();

    // In debug mode, surface the real underlying error so we can diagnose
    // provider issues (especially Azure's 401/403/400 messages for Kurdish)
    // without needing to scrape device logs.
    if (kDebugMode) {
      final trimmed = raw.length > 220 ? '${raw.substring(0, 220)}…' : raw;
      return 'Translation failed (debug): $trimmed';
    }

    if (lower.contains('api key') ||
        lower.contains('leak') ||
        lower.contains('permission_denied') ||
        lower.contains('forbidden') ||
        lower.contains('unauthorized') ||
        lower.contains('401') ||
        lower.contains('403')) {
      return 'Translation is temporarily unavailable due to a service configuration issue. Please try again later.';
    }

    if (lower.contains('resource_exhausted') ||
        lower.contains('quota') ||
        lower.contains('429')) {
      return 'Translation is busy right now. Please wait a moment and try again.';
    }

    if (lower.contains('socket') ||
        lower.contains('network') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('all providers failed')) {
      return 'Could not reach the translation service. Check your connection and try again.';
    }

    return 'Translation failed. Please try again in a little while.';
  }
>>>>>>> Stashed changes

  Future<String> translateText({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty || sourceLang == targetLang) {
      return normalized;
    }

<<<<<<< Updated upstream
    final key = dotenv.env['GEMINI_API_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception('GEMINI_API_KEY missing from .env');
=======
    final effectiveSourceLang = _effectiveSourceLang(
      sourceLang: sourceLang,
      text: normalized,
    );

    _tlog('translateText: src="$sourceLang" effSrc="$effectiveSourceLang" '
        'tgt="$targetLang" textLen=${normalized.length} '
        'sample="${normalized.substring(0, normalized.length > 40 ? 40 : normalized.length)}"');

    // Cache lookup — keyed on the *effective* source so an "auto" call that
    // resolves to ckb shares cache entries with a future explicit-ckb call.
    final cached = await _cacheLookup(
      sourceLang: effectiveSourceLang,
      targetLang: targetLang,
      text: normalized,
    );
    if (cached != null) {
      return cached;
    }

    final allProviders = _buildProviderList(
      sourceLang: effectiveSourceLang,
      targetLang: targetLang,
    );
    if (allProviders.isEmpty) {
      _tlog('ERROR: no providers configured for src=$effectiveSourceLang '
          'tgt=$targetLang. Check .env keys.');
      throw Exception('No translation providers configured');
>>>>>>> Stashed changes
    }

    final prompt =
        'Translate the following text from "$sourceLang" to "$targetLang". '
        'Return ONLY the translated text, with no quotes, no explanation, '
        'no prefix, no markdown.\n\nText:\n$normalized';

<<<<<<< Updated upstream
    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.2,
=======
    // For Kurdish-related translations, keep deterministic order so Gemini
    // is always attempted first (no rotation).
    final orderedProviders = kurdishInvolved
        ? allProviders
        : () {
            final startIndex = _providerIndex % allProviders.length;
            return [
              ...allProviders.sublist(startIndex),
              ...allProviders.sublist(0, startIndex),
            ];
          }();

    Exception? lastError;
    for (final provider in orderedProviders) {
      _tlog('attempting provider=$provider');
      try {
        final result = await _callProvider(
          provider: provider,
          text: normalized,
          sourceLang: effectiveSourceLang,
          targetLang: targetLang,
        );
        _tlog('SUCCESS via $provider, '
            'resultLen=${result.length} '
            'sample="${result.substring(0, result.length > 40 ? 40 : result.length)}"');
        _providerIndex = (_providerIndex + 1) % allProviders.length;
        // Persist for next time. Fire-and-forget — the result is already
        // returned to the caller; cache write happens in the background.
        unawaited(_cacheStore(
          sourceLang: effectiveSourceLang,
          targetLang: targetLang,
          text: normalized,
          result: result,
        ));
        return result;
      } on Exception catch (e) {
        _tlog('FAIL via $provider: $e');
        lastError = e;
        // Fall through to next provider.
>>>>>>> Stashed changes
      }
    };

    final isApiKey = key.startsWith('AIza');
    final uri = Uri.https(
      _host,
      '/v1beta/models/$_model:generateContent',
      isApiKey ? {'key': key} : null,
    );
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (!isApiKey) 'Authorization': 'Bearer $key',
    };

    final resp = await http.post(uri, headers: headers, body: jsonEncode(body));
    if (resp.statusCode != 200) {
      throw Exception('Gemini ${resp.statusCode}: ${resp.body}');
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('No candidates in Gemini response');
    }
    final content = (candidates.first as Map)['content'] as Map?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) {
      throw Exception('No parts in Gemini response');
    }
    final out = (parts.first as Map)['text'] as String?;
    if (out == null || out.trim().isEmpty) {
      throw Exception('Empty Gemini response');
    }
    return out.trim();
  }
}
