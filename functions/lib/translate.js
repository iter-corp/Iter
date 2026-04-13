"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.translateText = void 0;
const translate_1 = require("@google-cloud/translate");
const https_1 = require("firebase-functions/v2/https");
const supportedLangs = new Set(['en', 'ckb', 'ar', 'fa', 'tr']);
const translateClient = new translate_1.TranslationServiceClient();
exports.translateText = (0, https_1.onCall)(async (request) => {
    const text = String(request.data?.text ?? '').trim();
    const sourceLang = String(request.data?.sourceLang ?? 'en');
    const targetLang = String(request.data?.targetLang ?? 'en');
    if (text.length == 0) {
        throw new https_1.HttpsError('invalid-argument', 'text is required');
    }
    if (!supportedLangs.has(sourceLang) || !supportedLangs.has(targetLang)) {
        throw new https_1.HttpsError('invalid-argument', 'Unsupported language code');
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
            throw new https_1.HttpsError('internal', 'Translation provider returned no text');
        }
        return {
            translatedText,
            sourceLang,
            targetLang,
        };
    }
    catch (error) {
        console.error('translateText failed', { sourceLang, targetLang, error });
        throw new https_1.HttpsError('internal', 'Translation is unavailable. Configure Cloud Translate credentials and API access.');
    }
});
