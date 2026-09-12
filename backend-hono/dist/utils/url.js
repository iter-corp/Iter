import { env } from '../config/env.js';
const LEGACY_STORAGE_PREFIXES = [
    'https://htiwlasyspclmsyslaco.supabase.co/storage/v1/object/public',
    'http://localhost:3000/uploads',
    'http://127.0.0.1:3000/uploads',
];
/**
 * Normalizes any media URL pointing to legacy storage (e.g. decommissioned Supabase)
 * to point to the active backend storage endpoint (e.g. https://iterglobal.icu/uploads).
 */
export function normalizeMediaUrl(url) {
    if (!url || typeof url !== 'string')
        return null;
    const targetPrefix = env.STORAGE_PUBLIC_URL.replace(/\/+$/, '');
    for (const legacy of LEGACY_STORAGE_PREFIXES) {
        if (url.startsWith(legacy)) {
            return url.replace(legacy, targetPrefix);
        }
    }
    return url;
}
/**
 * Normalizes an array of media URLs.
 */
export function normalizeMediaUrls(urls) {
    if (!urls)
        return [];
    let parsed = [];
    if (Array.isArray(urls)) {
        parsed = urls;
    }
    else if (typeof urls === 'string') {
        try {
            const json = JSON.parse(urls);
            if (Array.isArray(json))
                parsed = json;
        }
        catch {
            return [];
        }
    }
    return parsed
        .filter((u) => typeof u === 'string' && u.trim().length > 0)
        .map((u) => normalizeMediaUrl(u) || u);
}
