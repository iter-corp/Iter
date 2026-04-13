import { TranslationServiceClient } from '@google-cloud/translate';
import { onCall, HttpsError } from 'firebase-functions/v2/https';

const supportedLangs = new Set(['en', 'ckb', 'ar', 'fa', 'tr']);
const translateClient = new TranslationServiceClient();

export const translateText = onCall(async (request) => {
  const text = String(request.data?.text ?? '').trim();
  const sourceLang = String(request.data?.sourceLang ?? 'en');
  const targetLang = String(request.data?.targetLang ?? 'en');

  if (text.length == 0) {
    throw new HttpsError('invalid-argument', 'text is required');
  }
  if (!supportedLangs.has(sourceLang) || !supportedLangs.has(targetLang)) {
    throw new HttpsError('invalid-argument', 'Unsupported language code');
  }
  if (sourceLang === targetLang) {
    return {
      translatedText: text,
      sourceLang,
      targetLang,
    };
  }

  try {
    const [response] = await translateClient.translateText({
      parent: `projects/${process.env.GCLOUD_PROJECT ?? process.env.GCP_PROJECT}/locations/global`,
      contents: [text],
      mimeType: 'text/plain',
      sourceLanguageCode: sourceLang,
      targetLanguageCode: targetLang,
    });

    const translatedText = response.translations?.[0]?.translatedText?.trim();
    if (!translatedText) {
      throw new HttpsError('internal', 'Translation provider returned no text');
    }

    return {
      translatedText,
      sourceLang,
      targetLang,
    };
  } catch (error) {
    console.error('translateText failed', { sourceLang, targetLang, error });
    throw new HttpsError(
      'internal',
      'Translation is unavailable. Configure Cloud Translate credentials and API access.',
    );
  }
});
