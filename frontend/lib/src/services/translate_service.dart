import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Translation via Google Gemini.
/// We ask Gemini to translate text, instructing it to return only the
/// translated text with no explanation or prefix.
class TranslateService {
  const TranslateService();

  static const _model = 'gemini-2.5-flash';
  static const _host = 'generativelanguage.googleapis.com';

  Future<String> translateText({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty || sourceLang == targetLang) {
      return normalized;
    }

    final key = dotenv.env['GEMINI_API_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception('GEMINI_API_KEY missing from .env');
    }

    final prompt =
        'Translate the following text from "$sourceLang" to "$targetLang". '
        'Return ONLY the translated text, with no quotes, no explanation, '
        'no prefix, no markdown.\n\nText:\n$normalized';

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
