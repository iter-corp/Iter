import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Tag prefix used by every debug print emitted by [TranslateService].
/// Search the device log with: `flutter logs | grep [translate]`
const String _kTranslateLogTag = '[translate]';

void _tlog(String msg) {
  if (kDebugMode) debugPrint('$_kTranslateLogTag $msg');
}

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
        return result;
      } on Exception catch (e) {
        _tlog('FAIL via $provider: $e');
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
    // For explicit Kurdish source (not auto-detect), treat as Kurdish too.
    final kurdishSource = sourceLang != 'auto' && _isKurdish(sourceLang);
    final involvesKurdish = kurdishTarget || kurdishSource;

    final geminiKey = dotenv.maybeGet('GEMINI_API_KEY') ?? '';
    final langblyKey = dotenv.maybeGet('LANGBLY_API_KEY') ?? '';
    final freeapiKey = dotenv.maybeGet('FREEAPITOOLS_API_KEY') ?? '';

    final azureKey = dotenv.maybeGet('AZURE_TRANSLATOR_KEY') ?? '';

    if (involvesKurdish) {
      // Kurdish: Azure (Microsoft) is the primary engine, but Sorani/Kurmanji
      // can fail on Azure due to region/quota/language-support issues. Fall
      // back to MyMemory (supports ckb/kmr) and Gemini so users still get
      // a translation while we diagnose Azure.
      final providers = <_Provider>[];
      if (azureKey.isNotEmpty) {
        providers.add(_Provider.azure);
      }
      providers.add(_Provider.mymemory);
      if (geminiKey.isNotEmpty) {
        providers.add(_Provider.gemini);
      }
      return providers;
    }

    // Non-Kurdish: Gemini first, then other AI fallbacks. Azure is added
    // last as a workhorse because it's reliable and has a generous free
    // tier — it kicks in if Gemini's model has rotated, MyMemory hits
    // its 403 daily quota, and so on. Without Azure here, comment/post
    // translate would silently fail for non-Kurdish text once the free
    // providers were exhausted.
    final providers = <_Provider>[];
    if (geminiKey.isNotEmpty) {
      providers.add(_Provider.gemini);
    }
    if (langblyKey.isNotEmpty) {
      providers.add(_Provider.langbly);
    }
    providers.add(_Provider.mymemory);
    if (freeapiKey.isNotEmpty) {
      providers.add(_Provider.freeapitools);
    }
    if (azureKey.isNotEmpty) {
      providers.add(_Provider.azure);
    }
    return providers;
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
    switch (provider) {
      case _Provider.azure:
        return _callAzure(
            text: text, sourceLang: sourceLang, targetLang: targetLang);
      case _Provider.gemini:
        return _callGemini(
            text: text, sourceLang: sourceLang, targetLang: targetLang);
      case _Provider.langbly:
        return _callLangbly(
            text: text, sourceLang: sourceLang, targetLang: targetLang);
      case _Provider.mymemory:
        return _callMyMemory(
            text: text, sourceLang: sourceLang, targetLang: targetLang);
      case _Provider.freeapitools:
        return _callFreeAPITools(
            text: text, sourceLang: sourceLang, targetLang: targetLang);
    }
  }

  // ──────────────────────────────────────────────
  // Provider implementations
  // ──────────────────────────────────────────────

  /// Microsoft Azure Translator. Used exclusively for Kurdish.
  /// Maps kmr → ku (Kurmanji/Northern Kurdish) so Azure accepts the code.
  Future<String> _callAzure({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final apiKey = dotenv.maybeGet('AZURE_TRANSLATOR_KEY') ?? '';
    if (apiKey.isEmpty) {
      throw Exception('Azure Translator key is missing');
    }
    final region =
        dotenv.maybeGet('AZURE_TRANSLATOR_REGION') ?? 'centralindia';
    final endpoint = (dotenv.maybeGet('AZURE_TRANSLATOR_ENDPOINT') ??
            'https://api.cognitive.microsofttranslator.com/')
        .replaceAll(RegExp(r'/$'), '');

    // Azure language-code mapping. Azure Translator uses `ku` for Central
    // Kurdish (Sorani). Kurmanji (Northern Kurdish, `kmr`) is NOT supported
    // by Azure — the caller will fall back to MyMemory/Gemini for that.
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

    _tlog('Azure REQUEST: '
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

    _tlog('Azure RESPONSE: status=${response.statusCode} '
        'elapsed=${stopwatch.elapsedMilliseconds}ms '
        'bodyLen=${response.body.length} '
        'body=${response.body.length > 500 ? "${response.body.substring(0, 500)}..." : response.body}');

    if (response.statusCode == 429) {
      throw Exception('Azure quota exceeded (429)');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception(
          'Azure unauthorized (${response.statusCode}) — check key/region. Body: ${response.body}');
    }
    if (response.statusCode != 200) {
      throw Exception('Azure error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body) as List;
    final translated =
        (decoded.first['translations'] as List?)?.first?['text'] as String?;
    if (translated == null || translated.trim().isEmpty) {
      _tlog('Azure returned empty translation. decoded=$decoded');
      throw Exception('Azure returned empty translation');
    }
    return translated.trim();
  }

  Future<String> _callGemini({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final apiKey = dotenv.maybeGet('GEMINI_API_KEY') ?? '';
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

  Future<String> _callLangbly({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final apiKey = dotenv.maybeGet('LANGBLY_API_KEY') ?? '';
    final response = await http
        .post(
          Uri.parse('https://api.langbly.com/language/translate/v2'),
          headers: {
            'Content-Type': 'application/json',
            'X-API-Key': apiKey,
          },
          body: jsonEncode({
            'q': text,
            'source': sourceLang,
            'target': targetLang,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 429) {
      throw Exception('Langbly quota exceeded (429)');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Langbly unauthorized (${response.statusCode})');
    }
    if (response.statusCode != 200) {
      throw Exception('Langbly error ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final translated = (decoded['data']?['translations'] as List?)
        ?.first?['translatedText'] as String?;
    if (translated == null || translated.trim().isEmpty) {
      throw Exception('Langbly returned empty translation');
    }
    return translated.trim();
  }

  /// MyMemory — free tier, no API key required.
  /// 1 000 words/day anonymous; supports ckb (Sorani) and kmr (Kurmanji).
  Future<String> _callMyMemory({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    // MyMemory uses "autodetect" for automatic source detection.
    final src = sourceLang == 'auto' ? 'autodetect' : sourceLang;
    final langPair = '$src|$targetLang';

    final uri = Uri.parse(
      'https://api.mymemory.translated.net/get',
    ).replace(queryParameters: {'q': text, 'langpair': langPair});

    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('MyMemory error ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final status = decoded['responseStatus'];
    // MyMemory returns 200 for success (as a number or string).
    if (status != 200 && status != '200') {
      throw Exception('MyMemory API error: $status');
    }

    final translated = decoded['responseData']?['translatedText'] as String?;
    if (translated == null || translated.trim().isEmpty) {
      throw Exception('MyMemory returned empty translation');
    }
    return translated.trim();
  }

  Future<String> _callFreeAPITools({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final apiKey = dotenv.maybeGet('FREEAPITOOLS_API_KEY') ?? '';
    final response = await http
        .post(
          Uri.parse('https://freeapitools.dev/api/v1/translate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'api_key': apiKey,
            'text': text,
            'source_language': sourceLang,
            'target_language': targetLang,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 403) {
      throw Exception('FreeAPITools forbidden (403)');
    }
    if (response.statusCode == 429) {
      throw Exception('FreeAPITools quota exceeded (429)');
    }
    if (response.statusCode != 200) {
      throw Exception('FreeAPITools error ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final translated = decoded['translated_text'] as String? ??
        decoded['translation'] as String?;
    if (translated == null || translated.trim().isEmpty) {
      throw Exception('FreeAPITools returned empty translation');
    }
    return translated.trim();
  }
}

enum _Provider { azure, gemini, langbly, mymemory, freeapitools }
