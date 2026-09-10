import { db } from '../db/index.js';
import { appConfigs } from '../db/schema/index.js';
import { eq } from 'drizzle-orm';
let cachedWords = null;
let lastCacheTime = 0;
const CACHE_TTL_MS = 60 * 1000; // 1 minute
export async function getProfanityList() {
    const now = Date.now();
    if (cachedWords && now - lastCacheTime < CACHE_TTL_MS) {
        return cachedWords;
    }
    try {
        const config = await db
            .select({ words: appConfigs.profanityWordsEn })
            .from(appConfigs)
            .where(eq(appConfigs.id, 'app'))
            .limit(1);
        const words = config[0]?.words || [
            'asshole', 'bastard', 'bitch', 'bullshit', 'damn', 'dick', 'fuck', 'fucker',
            'fucking', 'hell', 'motherfucker', 'piss', 'prick', 'shit', 'slut', 'whore'
        ];
        cachedWords = new Set(words.map((w) => w.toLowerCase().trim()));
        lastCacheTime = now;
        return cachedWords;
    }
    catch {
        return new Set(['fuck', 'shit', 'bitch', 'asshole']);
    }
}
export async function findProfanityMatches(text) {
    if (!text || text.trim().length === 0)
        return [];
    const blockedWords = await getProfanityList();
    const normalized = text.toLowerCase().replace(/[^a-z0-9\s]/g, ' ');
    const tokens = normalized.split(/\s+/).filter((t) => t.length > 0);
    const matched = new Set();
    for (const token of tokens) {
        if (blockedWords.has(token)) {
            matched.add(token);
        }
    }
    return Array.from(matched);
}
export function maskProfanity(text, matches) {
    let masked = text;
    for (const match of matches) {
        const regex = new RegExp(`\\b${match}\\b`, 'gi');
        masked = masked.replace(regex, '*'.repeat(match.length));
    }
    return masked;
}
