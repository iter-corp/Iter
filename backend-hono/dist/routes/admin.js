import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import { db } from '../db/index.js';
import { users, posts, events, postReports, commentReports, userReports, contactRequests, errorReports, apiKeys, apiLogs, appConfigs, blacklist } from '../db/schema/index.js';
import { eq, sql, desc, count } from 'drizzle-orm';
import { AppError } from '../middleware/error-handler.js';
import { requireAuth } from '../middleware/auth.js';
import { requireRole } from '../middleware/rbac.js';
import { sendPushNotification } from '../services/fcm.service.js';
import { randomBytes } from 'crypto';
import { env } from '../config/env.js';
import fs from 'fs/promises';
import path from 'path';
import bcrypt from 'bcryptjs';
export const adminRoutes = new Hono();
// ── Client Error Reporting (Public/Authenticated) ───────────────────────────
const errorReportSchema = z.object({
    error: z.string(),
    stackTrace: z.string().optional(),
    screen: z.string().optional(),
    appVersion: z.string().optional(),
    platform: z.string().optional(),
});
adminRoutes.post('/error-report', zValidator('json', errorReportSchema), async (c) => {
    const body = c.req.valid('json');
    const uid = c.get('uid');
    await db.insert(errorReports).values({
        id: `err_${randomBytes(12).toString('hex')}`,
        error: body.error,
        stackTrace: body.stackTrace || null,
        screen: body.screen || 'unknown',
        appVersion: body.appVersion || null,
        platform: body.platform || null,
        userUid: uid || null,
    });
    return c.json({ success: true });
});
// All following routes require ADMIN role
adminRoutes.use('/*', requireAuth, requireRole('admin'));
// ── 1. Dashboard Metrics / Statistics ───────────────────────────────────────
adminRoutes.get('/stats', async (c) => {
    const [[totalUsers], [totalPosts], [totalEvents], [openReports]] = await Promise.all([
        db.select({ count: count() }).from(users),
        db.select({ count: count() }).from(posts),
        db.select({ count: count() }).from(events),
        db.select({ count: count() }).from(postReports).where(eq(postReports.resolved, false)),
    ]);
    return c.json({
        success: true,
        data: {
            totalUsers: totalUsers?.count || 0,
            totalPosts: totalPosts?.count || 0,
            totalEvents: totalEvents?.count || 0,
            openReports: openReports?.count || 0,
        },
    });
});
// ── 2. Users Management ─────────────────────────────────────────────────────
adminRoutes.get('/users', async (c) => {
    const q = c.req.query('query')?.toLowerCase().trim();
    const limit = Math.min(Number(c.req.query('limit')) || 50, 200);
    const queryBuilder = db.select().from(users);
    if (q) {
        queryBuilder.where(sql `${users.usernameLower} LIKE ${'%' + q + '%'} OR ${users.email} LIKE ${'%' + q + '%'}`);
    }
    const userList = await queryBuilder.limit(limit);
    return c.json({ success: true, data: userList });
});
adminRoutes.patch('/users/:uid/suspend', async (c) => {
    const targetUid = c.req.param('uid');
    const body = await c.req.json();
    const suspended = Boolean(body.suspended);
    await db
        .update(users)
        .set({
        suspended,
        suspendedAt: suspended ? new Date() : null,
        suspendedBy: c.get('uid'),
    })
        .where(eq(users.id, targetUid));
    return c.json({ success: true, suspended });
});
adminRoutes.patch('/users/:uid/role', async (c) => {
    const targetUid = c.req.param('uid');
    const body = await c.req.json();
    const role = body.role; // 'user' | 'org_admin' | 'admin'
    if (!['user', 'org_admin', 'admin'].includes(role)) {
        throw new AppError('Invalid role', 400, 'INVALID_ROLE');
    }
    await db.update(users).set({ role }).where(eq(users.id, targetUid));
    // Push role update notification
    let title = 'Role Updated';
    let descText = `Your role has been updated to ${role}.`;
    if (role === 'admin') {
        title = 'Admin access granted';
        descText = 'Iter Team made you an administrator.';
    }
    else if (role === 'org_admin') {
        title = 'Event manager access granted';
        descText = 'Iter Team approved your organization manager access.';
    }
    await sendPushNotification({
        targetUid,
        title,
        body: descText,
        type: 'role_update',
    });
    return c.json({ success: true, role });
});
adminRoutes.post('/users/:uid/set-password', async (c) => {
    const targetUid = c.req.param('uid');
    const body = await c.req.json();
    const password = body.password;
    if (!password || typeof password !== 'string' || password.length < 6) {
        throw new AppError('Password must be at least 6 characters', 400, 'INVALID_PASSWORD');
    }
    const passwordHash = await bcrypt.hash(password, 10);
    await db.update(users).set({ passwordHash }).where(eq(users.id, targetUid));
    return c.json({ success: true, message: 'Password updated successfully' });
});
adminRoutes.post('/auth/seed-admins', async (c) => {
    const adminHash = await bcrypt.hash('Admin@123456', 10);
    const reviewerHash = await bcrypt.hash('IterReview2026!', 10);
    // Reviewer
    await db.insert(users).values({
        id: 'google_reviewer_admin_2026',
        email: 'google.reviewer@iter.app',
        emailVerified: true,
        passwordHash: reviewerHash,
        username: 'google.reviewer',
        usernameLower: 'google.reviewer',
        handle: '@google.reviewer',
        bio: 'Official Google Play App Reviewer (Super Admin)',
        role: 'admin',
        appIntroSeen: true,
    }).onDuplicateKeyUpdate({
        set: {
            role: 'admin',
            emailVerified: true,
            passwordHash: reviewerHash,
            username: 'google.reviewer',
            usernameLower: 'google.reviewer',
            handle: '@google.reviewer',
        }
    });
    // Root Admin
    await db.insert(users).values({
        id: 'admin_initial_root',
        email: 'admin@iter.app',
        emailVerified: true,
        passwordHash: adminHash,
        username: 'admin',
        usernameLower: 'admin',
        handle: '@admin',
        bio: 'Official Iter System Administrator',
        role: 'admin',
        appIntroSeen: true,
    }).onDuplicateKeyUpdate({
        set: {
            role: 'admin',
            emailVerified: true,
            passwordHash: adminHash,
        }
    });
    return c.json({ success: true, message: 'Super admins seeded successfully' });
});
// ── 3. Cascade Delete User ──────────────────────────────────────────────────
adminRoutes.delete('/users/:uid', async (c) => {
    const targetUid = c.req.param('uid');
    const [target] = await db.select().from(users).where(eq(users.id, targetUid)).limit(1);
    if (target) {
        if (target.email) {
            await db.insert(blacklist).ignore().values({
                emailOrDomain: target.email,
                reason: 'Admin cascade delete',
            });
        }
        // Cascade delete user row
        await db.delete(users).where(eq(users.id, targetUid));
    }
    return c.json({ success: true, message: 'User completely deleted and email blacklisted' });
});
// ── 4. Reports Moderation ───────────────────────────────────────────────────
adminRoutes.get('/reports', async (c) => {
    const [postReps, commentReps, userReps] = await Promise.all([
        db.select().from(postReports).where(eq(postReports.resolved, false)).limit(100),
        db.select().from(commentReports).where(eq(commentReports.resolved, false)).limit(100),
        db.select().from(userReports).where(eq(userReports.resolved, false)).limit(100),
    ]);
    return c.json({
        success: true,
        data: {
            postReports: postReps,
            commentReports: commentReps,
            userReports: userReps,
        },
    });
});
adminRoutes.patch('/reports/:type/:id/resolve', async (c) => {
    const type = c.req.param('type');
    const id = c.req.param('id');
    if (type === 'post') {
        await db.update(postReports).set({ resolved: true, resolvedAt: new Date() }).where(eq(postReports.id, id));
    }
    else if (type === 'comment') {
        await db.update(commentReports).set({ resolved: true, resolvedAt: new Date() }).where(eq(commentReports.id, id));
    }
    else if (type === 'user') {
        await db.update(userReports).set({ resolved: true, resolvedAt: new Date() }).where(eq(userReports.id, id));
    }
    return c.json({ success: true });
});
// ── 5. Contact Requests & Org Promotion ─────────────────────────────────────
adminRoutes.get('/contact-requests', async (c) => {
    const requests = await db.select().from(contactRequests).orderBy(desc(contactRequests.createdAt));
    return c.json({ success: true, data: requests });
});
adminRoutes.patch('/contact-requests/:id', async (c) => {
    const reqId = c.req.param('id');
    const body = await c.req.json();
    const { status, adminNotes } = body;
    await db
        .update(contactRequests)
        .set({
        status,
        adminNotes,
        repliedAt: new Date(),
        repliedBy: c.get('uid'),
    })
        .where(eq(contactRequests.id, reqId));
    const [contactReq] = await db.select().from(contactRequests).where(eq(contactRequests.id, reqId)).limit(1);
    if (contactReq && status === 'promoted') {
        await db.update(users).set({ role: 'org_admin' }).where(eq(users.id, contactReq.userUid));
        await sendPushNotification({
            targetUid: contactReq.userUid,
            title: 'Organization Access Approved',
            body: 'Your organization request has been approved! You can now publish events.',
            type: 'role_update',
        });
    }
    return c.json({ success: true, data: contactReq });
});
// ── 6. API Manager & AI Providers ───────────────────────────────────────────
adminRoutes.get('/api-keys', async (c) => {
    const keys = await db.select().from(apiKeys);
    const masked = keys.map((k) => ({
        ...k,
        key: k.key.length > 8 ? `${k.key.substring(0, 4)}••••${k.key.substring(k.key.length - 4)}` : '••••',
    }));
    return c.json({ success: true, data: masked });
});
adminRoutes.post('/api-keys', async (c) => {
    const body = await c.req.json();
    const { provider, key, priority } = body;
    const keyId = `key_${provider}_${randomBytes(6).toString('hex')}`;
    await db
        .insert(apiKeys)
        .values({
        id: keyId,
        provider,
        key,
        priority: Number(priority) || 10,
    });
    const [newKey] = await db.select().from(apiKeys).where(eq(apiKeys.id, keyId)).limit(1);
    return c.json({ success: true, data: newKey });
});
adminRoutes.delete('/api-keys/:id', async (c) => {
    const keyId = c.req.param('id');
    await db.delete(apiKeys).where(eq(apiKeys.id, keyId));
    return c.json({ success: true });
});
adminRoutes.get('/api-logs', async (c) => {
    const logs = await db.select().from(apiLogs).orderBy(desc(apiLogs.createdAt)).limit(100);
    return c.json({ success: true, data: logs });
});
// ── 7. Update App Config ────────────────────────────────────────────────────
adminRoutes.patch('/config', async (c) => {
    const body = await c.req.json();
    const { welcomeMessage, welcomeMessageEnabled, wikipediaEnabled, metadata: bodyMetadata, ...directFields } = body;
    const [existing] = await db.select().from(appConfigs).where(eq(appConfigs.id, 'app')).limit(1);
    const existingMetadata = existing?.metadata || {};
    const mergedMetadata = {
        ...existingMetadata,
        ...(bodyMetadata || {}),
        ...(welcomeMessage !== undefined ? { welcomeMessage } : {}),
        ...(welcomeMessageEnabled !== undefined ? { welcomeMessageEnabled } : {}),
        ...(wikipediaEnabled !== undefined ? { wikipediaEnabled } : {}),
    };
    await db
        .update(appConfigs)
        .set({
        ...directFields,
        metadata: mergedMetadata,
        updatedAt: new Date(),
    })
        .where(eq(appConfigs.id, 'app'));
    const [updated] = await db.select().from(appConfigs).where(eq(appConfigs.id, 'app')).limit(1);
    return c.json({ success: true, data: updated });
});
// ── 8. Media Synchronization & URL Migration ────────────────────────────────
adminRoutes.post('/media/fix-urls', async (c) => {
    const targetPrefix = env.STORAGE_PUBLIC_URL.replace(/\/+$/, '');
    const oldPrefixes = [
        'https://htiwlasyspclmsyslaco.supabase.co/storage/v1/object/public',
        'http://localhost:3000/uploads',
        'http://127.0.0.1:3000/uploads',
    ];
    const results = {};
    for (const oldPrefix of oldPrefixes) {
        if (oldPrefix === targetPrefix)
            continue;
        // 1. Users (avatar_url, cover_url)
        await db.execute(sql `
      UPDATE users SET 
        avatar_url = REPLACE(avatar_url, ${oldPrefix}, ${targetPrefix}),
        cover_url = REPLACE(cover_url, ${oldPrefix}, ${targetPrefix})
      WHERE avatar_url LIKE ${`%${oldPrefix}%`} OR cover_url LIKE ${`%${oldPrefix}%`}
    `);
        // 2. Posts (author_avatar)
        await db.execute(sql `
      UPDATE posts SET 
        author_avatar = REPLACE(author_avatar, ${oldPrefix}, ${targetPrefix})
      WHERE author_avatar LIKE ${`%${oldPrefix}%`}
    `);
        // 3. Posts (image_urls, video_urls JSON)
        const [rawPosts] = await db.execute(sql `
      SELECT id, image_urls, video_urls FROM posts 
      WHERE CAST(image_urls AS CHAR) LIKE ${`%${oldPrefix}%`} 
         OR CAST(video_urls AS CHAR) LIKE ${`%${oldPrefix}%`}
    `);
        if (Array.isArray(rawPosts)) {
            for (const row of rawPosts) {
                let imgs = [];
                let vids = [];
                if (typeof row.image_urls === 'string') {
                    try {
                        imgs = JSON.parse(row.image_urls);
                    }
                    catch { }
                }
                else if (Array.isArray(row.image_urls)) {
                    imgs = row.image_urls;
                }
                if (typeof row.video_urls === 'string') {
                    try {
                        vids = JSON.parse(row.video_urls);
                    }
                    catch { }
                }
                else if (Array.isArray(row.video_urls)) {
                    vids = row.video_urls;
                }
                const newImgs = imgs.map((u) => (typeof u === 'string' ? u.replace(oldPrefix, targetPrefix) : u));
                const newVids = vids.map((u) => (typeof u === 'string' ? u.replace(oldPrefix, targetPrefix) : u));
                await db.execute(sql `
          UPDATE posts SET 
            image_urls = ${JSON.stringify(newImgs)},
            video_urls = ${JSON.stringify(newVids)}
          WHERE id = ${row.id}
        `);
            }
            results[`posts_json_${oldPrefix}`] = rawPosts.length;
        }
        // 4. Comments
        await db.execute(sql `
      UPDATE comments SET 
        author_avatar = REPLACE(author_avatar, ${oldPrefix}, ${targetPrefix})
      WHERE author_avatar LIKE ${`%${oldPrefix}%`}
    `);
        // 5. Events
        await db.execute(sql `
      UPDATE events SET 
        cover_image_url = REPLACE(cover_image_url, ${oldPrefix}, ${targetPrefix})
      WHERE cover_image_url LIKE ${`%${oldPrefix}%`}
    `);
        // 6. Stories
        await db.execute(sql `
      UPDATE stories SET 
        image_url = REPLACE(image_url, ${oldPrefix}, ${targetPrefix}),
        video_url = REPLACE(video_url, ${oldPrefix}, ${targetPrefix}),
        author_avatar = REPLACE(author_avatar, ${oldPrefix}, ${targetPrefix})
      WHERE image_url LIKE ${`%${oldPrefix}%`} 
         OR video_url LIKE ${`%${oldPrefix}%`} 
         OR author_avatar LIKE ${`%${oldPrefix}%`}
    `);
    }
    return c.json({ success: true, targetPrefix, results });
});
adminRoutes.post('/media/sync-file', async (c) => {
    const bucket = c.req.query('bucket');
    const filePath = c.req.query('path');
    if (!bucket || !filePath) {
        throw new AppError('Missing bucket or path query parameters', 400, 'INVALID_REQUEST');
    }
    const allowedBuckets = new Set(['avatars', 'posts']);
    if (!allowedBuckets.has(bucket)) {
        throw new AppError(`Invalid bucket "${bucket}"`, 400, 'INVALID_BUCKET');
    }
    // Normalize path and prevent directory traversal
    const normalizedPath = path.normalize(filePath).replace(/^(\.\.[\/\\])+/, '');
    const localTarget = path.resolve(env.STORAGE_LOCAL_DIR, bucket, normalizedPath);
    await fs.mkdir(path.dirname(localTarget), { recursive: true });
    const arrayBuffer = await c.req.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);
    await fs.writeFile(localTarget, buffer);
    const publicUrl = `${env.STORAGE_PUBLIC_URL.replace(/\/+$/, '')}/${bucket}/${normalizedPath.replace(/\\/g, '/')}`;
    return c.json({ success: true, path: normalizedPath, publicUrl, size: buffer.length });
});
