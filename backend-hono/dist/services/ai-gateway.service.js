import { db } from '../db/index.js';
import { apiKeys, apiLogs } from '../db/schema/index.js';
import { eq, asc } from 'drizzle-orm';
import { env } from '../config/env.js';
export class AiGatewayService {
    /**
     * Fetches active API keys sorted by priority (lowest number = highest priority).
     */
    async getOrderedKeys() {
        const dbKeys = await db
            .select({
            id: apiKeys.id,
            provider: apiKeys.provider,
            key: apiKeys.key,
        })
            .from(apiKeys)
            .where(eq(apiKeys.active, true))
            .orderBy(asc(apiKeys.priority));
        if (dbKeys.length > 0) {
            return dbKeys;
        }
        // Fallback to environment keys if none configured in database
        const envList = [];
        if (env.GEMINI_API_KEY)
            envList.push({ id: 'env_gemini', provider: 'gemini', key: env.GEMINI_API_KEY });
        if (env.OPENAI_API_KEY)
            envList.push({ id: 'env_openai', provider: 'openai', key: env.OPENAI_API_KEY });
        if (env.ANTHROPIC_API_KEY)
            envList.push({ id: 'env_claude', provider: 'claude', key: env.ANTHROPIC_API_KEY });
        if (env.AZURE_TRANSLATOR_KEY)
            envList.push({ id: 'env_azure', provider: 'azure', key: env.AZURE_TRANSLATOR_KEY });
        return envList;
    }
    async translate(opts) {
        const { text, sourceLang, targetLang } = opts;
        if (sourceLang === targetLang) {
            return { translatedText: text, sourceLang, targetLang, provider: 'none', wasFallback: false };
        }
        const availableKeys = await this.getOrderedKeys();
        if (availableKeys.length === 0) {
            throw new Error('No AI translation providers configured');
        }
        let lastError = null;
        let wasFallback = false;
        for (let i = 0; i < availableKeys.length; i++) {
            const { id: keyId, provider, key } = availableKeys[i];
            const nextProvider = availableKeys[i + 1]?.provider;
            try {
                let translated = '';
                if (provider === 'gemini') {
                    translated = await this.callGemini(text, sourceLang, targetLang, key);
                }
                else if (provider === 'openai') {
                    translated = await this.callOpenAi(text, sourceLang, targetLang, key);
                }
                else if (provider === 'claude') {
                    translated = await this.callClaude(text, sourceLang, targetLang, key);
                }
                else if (provider === 'azure') {
                    translated = await this.callAzure(text, sourceLang, targetLang, key);
                }
                if (translated && translated.trim().length > 0) {
                    // Log success
                    await db.insert(apiLogs).values({
                        provider,
                        keyId,
                        success: true,
                        wasFallback,
                    });
                    return {
                        translatedText: translated.trim(),
                        sourceLang,
                        targetLang,
                        provider,
                        wasFallback,
                    };
                }
            }
            catch (err) {
                const errorMsg = err instanceof Error ? err.message : String(err);
                console.warn(`[AI Gateway] Provider '${provider}' failed:`, errorMsg);
                lastError = err instanceof Error ? err : new Error(errorMsg);
                // Log failure
                await db.insert(apiLogs).values({
                    provider,
                    keyId,
                    success: false,
                    wasFallback,
                    error: errorMsg,
                    nextProvider: nextProvider || null,
                });
                wasFallback = true;
            }
        }
        throw lastError || new Error('All translation providers failed');
    }
    async callGemini(text, sourceLang, targetLang, apiKey) {
        const model = 'gemini-2.0-flash';
        const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(apiKey)}`;
        const prompt = `Translate the following text from "${sourceLang}" to "${targetLang}". Return ONLY the translated text, with no quotes, no explanation, no prefix, no markdown.\n\nText:\n${text}`;
        const res = await fetch(endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                contents: [{ parts: [{ text: prompt }] }],
                generationConfig: { temperature: 0.2 },
            }),
        });
        if (!res.ok) {
            throw new Error(`Gemini status ${res.status}: ${await res.text()}`);
        }
        const data = (await res.json());
        return data.candidates?.[0]?.content?.parts?.[0]?.text?.trim() || '';
    }
    async callOpenAi(text, sourceLang, targetLang, apiKey) {
        const endpoint = 'https://api.openai.com/v1/chat/completions';
        const prompt = `Translate the following text from "${sourceLang}" to "${targetLang}". Return ONLY the translated text, no markdown or explanation.\n\nText:\n${text}`;
        const res = await fetch(endpoint, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: `Bearer ${apiKey}`,
            },
            body: JSON.stringify({
                model: 'gpt-4o-mini',
                messages: [{ role: 'user', content: prompt }],
                temperature: 0.2,
            }),
        });
        if (!res.ok) {
            throw new Error(`OpenAI status ${res.status}: ${await res.text()}`);
        }
        const data = (await res.json());
        return data.choices?.[0]?.message?.content?.trim() || '';
    }
    async callClaude(text, sourceLang, targetLang, apiKey) {
        const endpoint = 'https://api.anthropic.com/v1/messages';
        const prompt = `Translate the following text from "${sourceLang}" to "${targetLang}". Return ONLY the translated text, no quotes or explanation.\n\nText:\n${text}`;
        const res = await fetch(endpoint, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'x-api-key': apiKey,
                'anthropic-version': '2023-06-01',
            },
            body: JSON.stringify({
                model: 'claude-3-haiku-20240307',
                max_tokens: 1000,
                messages: [{ role: 'user', content: prompt }],
            }),
        });
        if (!res.ok) {
            throw new Error(`Claude status ${res.status}: ${await res.text()}`);
        }
        const data = (await res.json());
        return data.content?.[0]?.text?.trim() || '';
    }
    async callAzure(text, sourceLang, targetLang, apiKey) {
        const region = env.AZURE_TRANSLATOR_REGION || 'global';
        const endpoint = `https://api.cognitive.microsofttranslator.com/translate?api-version=3.0&from=${encodeURIComponent(sourceLang)}&to=${encodeURIComponent(targetLang)}`;
        const res = await fetch(endpoint, {
            method: 'POST',
            headers: {
                'Ocp-Apim-Subscription-Key': apiKey,
                'Ocp-Apim-Subscription-Region': region,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify([{ text }]),
        });
        if (!res.ok) {
            throw new Error(`Azure status ${res.status}: ${await res.text()}`);
        }
        const data = (await res.json());
        return data[0]?.translations?.[0]?.text?.trim() || '';
    }
}
export const aiGateway = new AiGatewayService();
