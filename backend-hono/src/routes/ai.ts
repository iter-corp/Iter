import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import { aiGateway } from '../services/ai-gateway.service.js';
import { requireAuth } from '../middleware/auth.js';
import { env } from '../config/env.js';

export const aiRoutes = new Hono();

// ── 1. Translation with Multi-Provider Fallback ─────────────────────────────
const translateSchema = z.object({
  text: z.string().min(1).max(5000),
  sourceLang: z.string().min(2),
  targetLang: z.string().min(2),
});

aiRoutes.post('/translate', requireAuth, zValidator('json', translateSchema), async (c) => {
  const { text, sourceLang, targetLang } = c.req.valid('json');

  const result = await aiGateway.translate({
    text,
    sourceLang,
    targetLang,
  });

  return c.json({ success: true, data: result });
});

// ── 2. NASA APOD Feed Proxy & Caching ───────────────────────────────────────
let apodCache: { data: unknown; timestamp: number } | null = null;
const APOD_CACHE_TTL_MS = 60 * 60 * 1000; // 1 hour

aiRoutes.get('/nasa-apod', async (c) => {
  const now = Date.now();
  if (apodCache && now - apodCache.timestamp < APOD_CACHE_TTL_MS) {
    return c.json({ success: true, data: apodCache.data });
  }

  const count = Math.min(Number(c.req.query('count')) || 10, 30);
  const endpoint = `https://api.nasa.gov/planetary/apod?api_key=${encodeURIComponent(env.NASA_API_KEY)}&count=${count}&thumbs=true`;

  try {
    const res = await fetch(endpoint);
    if (!res.ok) throw new Error(`NASA API returned status ${res.status}`);
    const items = await res.json();

    apodCache = { data: items, timestamp: now };
    return c.json({ success: true, data: items });
  } catch (err: unknown) {
    if (apodCache) {
      return c.json({ success: true, data: apodCache.data, cached: true });
    }
    return c.json({ success: false, error: { message: (err as Error).message } }, 502);
  }
});
