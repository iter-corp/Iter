import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import { db } from '../db/index.js';
import { notifications, fcmTokens } from '../db/schema/index.js';
import { eq, and, desc, sql } from 'drizzle-orm';
import { requireAuth } from '../middleware/auth.js';
export const notificationRoutes = new Hono();
// ── 1. Get Notification Inbox ───────────────────────────────────────────────
notificationRoutes.get('/', requireAuth, async (c) => {
    const uid = c.get('uid');
    const limit = Math.min(Number(c.req.query('limit')) || 50, 100);
    const items = await db
        .select()
        .from(notifications)
        .where(eq(notifications.targetUid, uid))
        .orderBy(desc(notifications.createdAt))
        .limit(limit);
    return c.json({ success: true, data: items });
});
// ── 2. Get Unread Count ─────────────────────────────────────────────────────
notificationRoutes.get('/unread-count', requireAuth, async (c) => {
    const uid = c.get('uid');
    const [result] = await db
        .select({ count: sql `count(*)::int` })
        .from(notifications)
        .where(and(eq(notifications.targetUid, uid), eq(notifications.read, false)));
    return c.json({ success: true, count: result?.count || 0 });
});
// ── 3. Mark Single Notification Read ────────────────────────────────────────
notificationRoutes.post('/:id/read', requireAuth, async (c) => {
    const uid = c.get('uid');
    const notifId = c.req.param('id');
    await db
        .update(notifications)
        .set({ read: true })
        .where(and(eq(notifications.id, notifId), eq(notifications.targetUid, uid)));
    return c.json({ success: true });
});
// ── 4. Mark All Read ────────────────────────────────────────────────────────
notificationRoutes.post('/read-all', requireAuth, async (c) => {
    const uid = c.get('uid');
    await db
        .update(notifications)
        .set({ read: true })
        .where(and(eq(notifications.targetUid, uid), eq(notifications.read, false)));
    return c.json({ success: true });
});
// ── 5. Register or Update FCM Token ─────────────────────────────────────────
const fcmTokenSchema = z.object({
    token: z.string().min(10),
    deviceType: z.enum(['ios', 'android', 'web']).default('android'),
});
notificationRoutes.post('/fcm-token', requireAuth, zValidator('json', fcmTokenSchema), async (c) => {
    const uid = c.get('uid');
    const { token, deviceType } = c.req.valid('json');
    await db
        .insert(fcmTokens)
        .values({
        uid,
        token,
        deviceType,
        updatedAt: new Date(),
    })
        .onDuplicateKeyUpdate({
        set: {
            uid,
            deviceType,
            updatedAt: new Date(),
        },
    });
    return c.json({ success: true, message: 'FCM token registered' });
});
// ── 6. Remove FCM Token (on Signout) ────────────────────────────────────────
notificationRoutes.delete('/fcm-token', requireAuth, async (c) => {
    const uid = c.get('uid');
    const body = await c.req.json().catch(() => ({}));
    const token = body?.token;
    if (token) {
        await db.delete(fcmTokens).where(and(eq(fcmTokens.uid, uid), eq(fcmTokens.token, token)));
    }
    return c.json({ success: true, message: 'FCM token removed' });
});
