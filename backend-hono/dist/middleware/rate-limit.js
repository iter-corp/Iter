import { AppError } from './error-handler.js';
const store = new Map();
export function rateLimit(options) {
    const { maxRequests, windowSeconds } = options;
    const windowMs = windowSeconds * 1000;
    return async (c, next) => {
        const ip = c.req.header('x-forwarded-for')?.split(',')[0].trim() ||
            c.req.header('x-real-ip') ||
            'unknown-ip';
        const key = `${ip}:${c.req.path}`;
        const now = Date.now();
        const record = store.get(key);
        if (!record || now > record.resetTime) {
            store.set(key, {
                count: 1,
                resetTime: now + windowMs,
            });
        }
        else {
            record.count += 1;
            if (record.count > maxRequests) {
                const retryAfter = Math.ceil((record.resetTime - now) / 1000);
                c.header('Retry-After', String(retryAfter));
                throw new AppError('Too many requests. Please slow down.', 429, 'RATE_LIMIT_EXCEEDED', { retryAfter });
            }
        }
        // Periodic cleanup of expired records
        if (store.size > 5000) {
            for (const [k, v] of store.entries()) {
                if (now > v.resetTime)
                    store.delete(k);
            }
        }
        await next();
    };
}
