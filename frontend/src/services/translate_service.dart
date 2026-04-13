import 'package:cloud_functions/cloud_functions.dart';

class TranslateService {
  final FirebaseFunctions _functions;

  TranslateService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  Future<String> translateText({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final callable = _functions.httpsCallable('translateText');
    final result = await callable.call({
      'text': text,
      'sourceLang': sourceLang,
      'targetLang': targetLang,
    });

    final data = result.data;
    if (data is Map && data['translatedText'] is String) {
      return data['translatedText'] as String;
    }
    throw Exception('Invalid translation response');
  }
}
