"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.translateText = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
// Stored via `firebase functions:secrets:set GEMINI_API_KEY`.
// Never shipped to clients — the key lives only in the Cloud Function runtime.
const geminiApiKey = (0, params_1.defineSecret)('GEMINI_API_KEY');
const model = 'gemini-2.5-flash';
const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
exports.translateText = (0, https_1.onCall)({ secrets: [geminiApiKey] }, async (request) => {
    if (!request.auth?.uid) {
        throw new https_1.HttpsError('unauthenticated', 'Sign in required');
    }
    const text = String(request.data?.text ?? '').trim();
    const sourceLang = String(request.data?.sourceLang ?? '').trim();
    const targetLang = String(request.data?.targetLang ?? '').trim();
    if (text.length === 0) {
        throw new https_1.HttpsError('invalid-argument', 'text is required');
    }
    if (sourceLang.length === 0 || targetLang.length === 0) {
        throw new https_1.HttpsError('invalid-argument', 'sourceLang and targetLang are required');
    }
    if (sourceLang === targetLang) {
        return { translatedText: text, sourceLang, targetLang };
    }
    const key = geminiApiKey.value();
    if (!key) {
        throw new https_1.HttpsError('failed-precondition', 'GEMINI_API_KEY not configured');
    }
    const prompt = `Translate the following text from "${sourceLang}" to "${targetLang}". ` +
        'Return ONLY the translated text, with no quotes, no explanation, ' +
        `no prefix, no markdown.\n\nText:\n${text}`;
    const body = {
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.2 },
    };
    const url = `${endpoint}?key=${encodeURIComponent(key)}`;
    let resp;
    try {
        resp = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        });
    }
    catch (err) {
        console.error('gemini fetch failed', err);
        throw new https_1.HttpsError('unavailable', 'Translation service unreachable');
    }
    if (!resp.ok) {
        const errText = await resp.text();
        console.error('gemini non-200', resp.status, errText);
        if (resp.status === 401 || resp.status === 403) {
            throw new https_1.HttpsError('internal', 'Translation service auth error');
        }
        if (resp.status === 429) {
            throw new https_1.HttpsError('resource-exhausted', 'Translation quota exceeded');
        }
        throw new https_1.HttpsError('internal', 'Translation failed');
    }
    const decoded = (await resp.json());
    const translated = decoded.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
    if (!translated) {
        throw new https_1.HttpsError('internal', 'Translation returned empty response');
    }
    return { translatedText: translated, sourceLang, targetLang };
});
