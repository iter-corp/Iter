import 'dart:convert';

import 'package:http/http.dart' as http;

class TranslateService {
  const TranslateService();

  Future<String> translateText({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty || sourceLang == targetLang) {
      return normalizedText;
    }

    final uri = Uri.https(
      'translate.googleapis.com',
      '/translate_a/single',
      {
        'client': 'gtx',
        'sl': sourceLang,
        'tl': targetLang,
        'dt': 't',
        'q': normalizedText,
      },
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Translation request failed (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty || decoded.first is! List) {
      throw Exception('Invalid translation response');
    }

    final segments = decoded.first as List;
    final translated = segments
        .whereType<List>()
        .map((segment) => segment.isNotEmpty ? segment.first : null)
        .whereType<String>()
        .join();

    if (translated.isEmpty) {
      throw Exception('Empty translation result');
    }

    return translated;
  }
}
