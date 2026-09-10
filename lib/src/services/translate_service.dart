import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// Tag prefix used by every debug print emitted by [TranslateService].
/// Search the device log with: `flutter logs | grep [translate]`
const String _kTranslateLogTag = '[translate]';

// ─────────────────────────────────────────────────────────────────────────────
// API Key Store — reads active keys from Firestore `apiKeys` collection and
// falls back to .env values when Firestore has nothing configured.
//
// The store keeps a live subscription so key changes (add / disable / delete)
// in the admin panel take effect in the running app within seconds.
// ─────────────────────────────────────────────────────────────────────────────

class _ApiKeyStore {
  _ApiKeyStore._();
  static final _ApiKeyStore instance = _ApiKeyStore._();

  // All active key docs in global priority order (sorted by `priority` asc).
  // Each map: { 'id', 'key', 'provider', 'priority', 'statusMessage' }
  final List<Map<String, dynamic>> _allKeys = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  bool _initialized = false;

  final _db = FirebaseFirestore.instance;

  /// Start listening to Firestore. Safe to call multiple times.
  void init() {
    if (_initialized) return;
    _initialized = true;
    _sub = _db
        .collection('apiKeys')
        .where('active', isEqualTo: true)
        .orderBy('priority')
        .snapshots()
        .listen(
      (snap) {
        _allKeys
          ..clear()
          ..addAll(snap.docs.map((doc) {
            final d = doc.data();
            return {
              'id': doc.id,
              'key': (d['key'] as String? ?? '').trim(),
              'provider': (d['provider'] as String? ?? '').toLowerCase(),
              'priority': (d['priority'] as num?)?.toInt() ?? 999,
              'statusMessage': (d['statusMessage'] as String?) ?? '',
            };
          }));
        _tlog('ApiKeyStore updated: ${_allKeys.length} active keys '
            '${_allKeys.map((k) => "${k["provider"]}#${k["priority"]}").join(", ")}');
      },
      onError: (e) => _tlog('ApiKeyStore stream error: $e'),
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
    _allKeys.clear();
  }

  /// Returns all active key entries for [provider] in priority order,
  /// falling back to .env values if Firestore has nothing for that provider.
  List<Map<String, dynamic>> docsFor(String provider) {
    final p = provider.toLowerCase();
    final fromFirestore =
        _allKeys.where((d) => d['provider'] == p).toList();
    if (fromFirestore.isNotEmpty) return fromFirestore;

    // .env fallback — keeps working before admin populates Firestore.
    final envKeys = <String>[];
    switch (p) {
      case 'gemini':
        final k = dotenv.maybeGet('GEMINI_API_KEY') ?? '';
        if (k.isNotEmpty) envKeys.add(k);
      case 'azure':
        final k1 = dotenv.maybeGet('AZURE_TRANSLATOR_KEY') ?? '';
        final k2 = dotenv.maybeGet('AZURE_TRANSLATOR_KEY_2') ?? '';
        if (k1.isNotEmpty) envKeys.add(k1);
        if (k2.isNotEmpty) envKeys.add(k2);
    }
    return envKeys
        .map((k) => {'id': '', 'key': k, 'provider': p, 'priority': 999,
                      'statusMessage': ''})
        .toList();
  }

  /// Convenience: just the key strings.
  List<String> keysFor(String provider) =>
      docsFor(provider).map((d) => d['key'] as String).toList();

  /// The full ordered list across ALL providers — used by _buildProviderList
  /// to respect the admin-set cross-provider ordering (e.g. Azure key ranked
  /// #1 even though Gemini is a different provider).
  List<Map<String, dynamic>> get allKeysSorted => _allKeys;

  // ── Status helpers ──────────────────────────────────────────────────────

  void markKeyFailed(String docId, String error) {
    if (docId.isEmpty) return;
    _db.collection('apiKeys').doc(docId).update({
      'statusMessage': error.length > 300 ? error.substring(0, 300) : error,
      'lastChecked': FieldValue.serverTimestamp(),
    }).catchError((_) {});
  }

  void markKeyOk(String docId, String currentStatus) {
    if (docId.isEmpty || currentStatus.isEmpty) return;
    _db.collection('apiKeys').doc(docId).update({
      'statusMessage': null,
      'lastChecked': FieldValue.serverTimestamp(),
    }).catchError((_) {});
  }

  // ── API log ─────────────────────────────────────────────────────────────

  void writeLog({
    required String provider,
    required String keyId,
    required bool success,
    required bool wasFallback,
    String? error,
    String? nextProvider,
  }) {
    _db.collection('apiLogs').add({
      'provider': provider,
      'keyId': keyId,
      'success': success,
      'wasFallback': wasFallback,
      if (error != null)
        'error': error.length > 300 ? error.substring(0, 300) : error,
      if (nextProvider != null) 'nextProvider': nextProvider,
      'createdAt': FieldValue.serverTimestamp(),
    }).ignore();
  }
}

/// Call this once from main.dart (after Firebase.initializeApp) so the key
/// store starts listening before the first translation is requested.
void initApiKeyStore() => _ApiKeyStore.instance.init();

void _tlog(String msg) {
  if (kDebugMode) debugPrint('$_kTranslateLogTag $msg');
}

/// Metadata for a translation target language.
///
/// [code] is the BCP-47 / Azure language code passed to
/// [TranslateService.translateText]. [label] is the human-readable name
/// shown in pickers. [stt] is the speech-to-text locale (`xx_YY` form) for
/// the in-app live translator's mic input — `null` means the device default
/// is used. [rtl] is true for right-to-left scripts.
class TranslateLanguage {
  final String code;
  final String label;
  final String? stt;
  final bool rtl;
  const TranslateLanguage(this.code, this.label, {this.stt, this.rtl = false});
}

/// Single source of truth for every language picker in the app: chat
/// auto-translate dropdown, comment translate sheet, post-caption
/// translate sheet, and the dedicated translate screen. Edit here once
/// and every picker updates.
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
///  - Kurdish involved (source or target) -> Azure key 1, Azure key 2, Gemini
///  - All other languages -> Gemini, Azure key 1, Azure key 2
///
/// Kurdish codes: ku, ckb (Sorani), kmr (Kurmanji) and any subtag variants.
class TranslateService {
  const TranslateService();

  // ──────────────────────────────────────────────
  // On-device translation cache
  // ──────────────────────────────────────────────
  // Same translation request hits SharedPreferences first; only misses go to
  // network providers. Single JSON blob keyed `<src>|<tgt>|<sha1(text)>`.
  // Capped at [_kCacheMaxEntries] — on overflow we drop the whole cache
  // (cheaper than per-entry LRU bookkeeping for the size we care about).
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
          _cache = decoded is Map
              ? decoded.map((k, v) => MapEntry(k.toString(), v.toString()))
              : <String, String>{};
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
    if (hit != null) _tlog('cache HIT len=${hit.length}');
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

  /// Clears all cached translations (memory + disk).
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

  Future<String> translateText({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty || sourceLang == targetLang) {
      return normalized;
    }

    final effectiveSourceLang = _effectiveSourceLang(
      sourceLang: sourceLang,
      text: normalized,
    );

    _tlog('translateText: src="$sourceLang" effSrc="$effectiveSourceLang" '
        'tgt="$targetLang" textLen=${normalized.length} '
        'sample="${normalized.substring(0, normalized.length > 40 ? 40 : normalized.length)}"');

    // Cache lookup — keyed on the *effective* source so an "auto" call
    // that resolves to ckb shares cache entries with a future explicit-ckb
    // call. Hits return instantly without touching any network provider.
    final cached = await _cacheLookup(
      sourceLang: effectiveSourceLang,
      targetLang: targetLang,
      text: normalized,
    );
    if (cached != null) {
      return cached;
    }

    try {
      final res = await ApiClient.instance.post('/ai/translate', body: {
        'text': normalized,
        'sourceLanguage': effectiveSourceLang,
        'targetLanguage': targetLang,
      });
      if (res is Map<String, dynamic> && res.containsKey('translatedText')) {
        final translated = res['translatedText'] as String;
        await _cacheStore(
          sourceLang: effectiveSourceLang,
          targetLang: targetLang,
          text: normalized,
          result: translated,
        );
        return translated;
      }
    } catch (e) {
      _tlog('Hono backend translation error: $e — checking local providers');
    }

    final allProviders = _buildProviderList(
      sourceLang: effectiveSourceLang,
      targetLang: targetLang,
    );
    if (allProviders.isEmpty) {
      _tlog('ERROR: no providers configured for src=$effectiveSourceLang '
          'tgt=$targetLang. Check .env keys.');
      throw Exception('No translation providers configured');
    }

    final kurdishInvolved =
        _isKurdish(effectiveSourceLang) || _isKurdish(targetLang);
    _tlog('kurdishInvolved=$kurdishInvolved providers=$allProviders');

    final store = _ApiKeyStore.instance;
    Exception? lastError;
    for (var i = 0; i < allProviders.length; i++) {
      final provider = allProviders[i];
      _tlog('attempting provider=$provider');
      final providerName = provider == _Provider.gemini ? 'gemini' : 'azure';
      final docs = store.docsFor(providerName);
      // azurePrimary → docs[0], azureSecondary → docs[1] (if present).
      final docIndex = provider == _Provider.azureSecondary ? 1 : 0;
      final usedDoc = docs.length > docIndex ? docs[docIndex] : null;
      final usedDocId = usedDoc?['id'] as String? ?? '';
      final currentStatus = usedDoc?['statusMessage'] as String? ?? '';
      final wasFallback = i > 0;
      // The next provider name (for the log entry), if there is one.
      final nextProviderName = i + 1 < allProviders.length
          ? (allProviders[i + 1] == _Provider.gemini ? 'gemini' : 'azure')
          : null;
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
        // Clear any previous failure status for this key.
        store.markKeyOk(usedDocId, currentStatus);
        // Write success log (only log fallback successes to reduce noise).
        if (wasFallback) {
          store.writeLog(
            provider: providerName,
            keyId: usedDocId,
            success: true,
            wasFallback: true,
          );
        }
        unawaited(_cacheStore(
          sourceLang: effectiveSourceLang,
          targetLang: targetLang,
          text: normalized,
          result: result,
        ));
        return result;
      } on Exception catch (e) {
        _tlog('FAIL via $provider: $e');
        store.markKeyFailed(usedDocId, e.toString());
        store.writeLog(
          provider: providerName,
          keyId: usedDocId,
          success: false,
          wasFallback: wasFallback,
          error: e.toString(),
          nextProvider: nextProviderName,
        );
        lastError = e;
        // Fall through to next provider.
      }
    }

    _tlog('ALL PROVIDERS FAILED. lastError=$lastError');
    throw lastError ?? Exception('All providers failed');
  }

  // ──────────────────────────────────────────────
  // Provider list builder
  // ──────────────────────────────────────────────

  List<_Provider> _buildProviderList({
    required String sourceLang,
    required String targetLang,
  }) {
    final kurdishTarget = _isKurdish(targetLang);
    final kurdishSource = sourceLang != 'auto' && _isKurdish(sourceLang);
    final involvesKurdish = kurdishTarget || kurdishSource;

    final store = _ApiKeyStore.instance;
    final hasGemini = store.keysFor('gemini').isNotEmpty;
    final azureKeys = store.keysFor('azure');

    // Build one _Provider per Azure key (index-based so we can try each key).
    final azureProviders = List.generate(
      azureKeys.length,
      (i) => i == 0 ? _Provider.azurePrimary : _Provider.azureSecondary,
    );

    if (involvesKurdish) {
      // Kurdish: Azure first (best Kurdish support), Gemini as fallback.
      return [
        ...azureProviders,
        if (hasGemini) _Provider.gemini,
      ];
    }

    // Non-Kurdish: Gemini first, Azure as fallback.
    return [
      if (hasGemini) _Provider.gemini,
      ...azureProviders,
    ];
  }

  // ──────────────────────────────────────────────
  // Provider dispatch
  // ──────────────────────────────────────────────

  Future<String> _callProvider({
    required _Provider provider,
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final store = _ApiKeyStore.instance;
    switch (provider) {
      case _Provider.azurePrimary:
        final keys = store.keysFor('azure');
        final key = keys.isNotEmpty ? keys.first : '';
        return _callAzure(
          apiKey: key,
          // Region / endpoint: still read from .env as optional overrides;
          // if not set, the defaults below apply.
          region: dotenv.maybeGet('AZURE_TRANSLATOR_REGION') ?? 'centralindia',
          endpoint: (dotenv.maybeGet('AZURE_TRANSLATOR_ENDPOINT') ??
                  'https://api.cognitive.microsofttranslator.com/')
              .replaceAll(RegExp(r'/$'), ''),
          providerLabel: 'Azure primary',
          text: text,
          sourceLang: sourceLang,
          targetLang: targetLang,
        );
      case _Provider.azureSecondary:
        final keys = store.keysFor('azure');
        final key = keys.length > 1 ? keys[1] : '';
        return _callAzure(
          apiKey: key,
          region: dotenv.maybeGet('AZURE_TRANSLATOR_REGION_2') ??
              dotenv.maybeGet('AZURE_TRANSLATOR_REGION') ??
              'centralindia',
          endpoint: (dotenv.maybeGet('AZURE_TRANSLATOR_ENDPOINT_2') ??
                  dotenv.maybeGet('AZURE_TRANSLATOR_ENDPOINT') ??
                  'https://api.cognitive.microsofttranslator.com/')
              .replaceAll(RegExp(r'/$'), ''),
          providerLabel: 'Azure secondary',
          text: text,
          sourceLang: sourceLang,
          targetLang: targetLang,
        );
      case _Provider.gemini:
        final keys = store.keysFor('gemini');
        final key = keys.isNotEmpty ? keys.first : '';
        return _callGemini(
          apiKey: key,
          text: text,
          sourceLang: sourceLang,
          targetLang: targetLang,
        );
    }
  }

  // ──────────────────────────────────────────────
  // Provider implementations
  // ──────────────────────────────────────────────

  /// Microsoft Azure Translator. Primary for Kurdish, fallback otherwise.
  /// Maps ckb to ku for Azure; kmr falls through to Gemini because Azure
  /// does not support Kurmanji.
  Future<String> _callAzure({
    required String apiKey,
    required String region,
    required String endpoint,
    required String providerLabel,
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    if (apiKey.isEmpty) {
      throw Exception('$providerLabel Translator key is missing');
    }

    // Azure language-code mapping. Azure Translator uses `ku` for Central
    // Kurdish (Sorani). Kurmanji (Northern Kurdish, `kmr`) is NOT supported
    // by Azure - the caller will fall back to Gemini for that.
    String mapLang(String code) {
      final l = code.toLowerCase();
      if (l == 'ckb' || l.startsWith('ckb-')) return 'ku';
      if (l == 'kmr' || l.startsWith('kmr-')) {
        throw Exception(
            'Azure does not support Kurmanji (kmr); falling back to next provider');
      }
      return code;
    }

    final mappedTarget = mapLang(targetLang);
    final mappedSource = sourceLang == 'auto' ? null : mapLang(sourceLang);

    final query = <String, String>{
      'api-version': '3.0',
      'to': mappedTarget,
    };
    if (mappedSource != null) {
      query['from'] = mappedSource;
    }

    final uri =
        Uri.parse('$endpoint/translate').replace(queryParameters: query);

    _tlog('$providerLabel REQUEST: '
        'endpoint=$endpoint region=$region '
        'from=${mappedSource ?? "(auto)"} to=$mappedTarget '
        'keyPrefix=${apiKey.substring(0, apiKey.length > 6 ? 6 : apiKey.length)}... '
        'uri=$uri');

    final stopwatch = Stopwatch()..start();
    final response = await http
        .post(
          uri,
          headers: {
            'Ocp-Apim-Subscription-Key': apiKey,
            'Ocp-Apim-Subscription-Region': region,
            'Content-Type': 'application/json',
          },
          body: jsonEncode([
            {'Text': text}
          ]),
        )
        .timeout(const Duration(seconds: 20));
    stopwatch.stop();

    _tlog('$providerLabel RESPONSE: status=${response.statusCode} '
        'elapsed=${stopwatch.elapsedMilliseconds}ms '
        'bodyLen=${response.body.length} '
        'body=${response.body.length > 500 ? "${response.body.substring(0, 500)}..." : response.body}');

    if (response.statusCode == 429) {
      throw Exception('$providerLabel quota exceeded (429)');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception(
          '$providerLabel unauthorized (${response.statusCode}) - check key/region. Body: ${response.body}');
    }
    if (response.statusCode != 200) {
      throw Exception(
          '$providerLabel error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as List;
    final translated =
        (decoded.first['translations'] as List?)?.first?['text'] as String?;
    if (translated == null || translated.trim().isEmpty) {
      _tlog('$providerLabel returned empty translation. decoded=$decoded');
      throw Exception('$providerLabel returned empty translation');
    }
    return translated.trim();
  }

  Future<String> _callGemini({
    required String apiKey,
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    if (apiKey.isEmpty) {
      throw Exception('Gemini API key is missing');
    }

    final src = sourceLang == 'auto' ? 'detected source language' : sourceLang;
    final prompt = '''You are a precise translation engine.
Translate the following text from $src to $targetLang.
Return only the translated text.
Text:
$text''';

    final response = await http
        .post(
          Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt}
                ]
              }
            ],
            'generationConfig': {
              'temperature': 0,
              'topP': 0.1,
              'maxOutputTokens': 2048,
            }
          }),
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode == 429) {
      throw Exception('Gemini quota exceeded (429)');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Gemini unauthorized (${response.statusCode})');
    }
    if (response.statusCode != 200) {
      throw Exception('Gemini error ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    final translated = candidates?.firstWhere((_) => true,
        orElse: () => null)?['content']?['parts']?[0]?['text'] as String?;

    if (translated == null || translated.trim().isEmpty) {
      throw Exception('Gemini returned empty translation');
    }
    return translated.trim();
  }
}

enum _Provider { azurePrimary, azureSecondary, gemini }
