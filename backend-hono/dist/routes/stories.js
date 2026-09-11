import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import { db } from '../db/index.js';
import { stories, storyViewers, storyLikes, users } from '../db/schema/index.js';
import { eq, sql, desc, gt } from 'drizzle-orm';
import { AppError } from '../middleware/error-handler.js';
import { requireAuth, optionalAuth } from '../middleware/auth.js';
import { randomBytes } from 'crypto';
export const storyRoutes = new Hono();
// ── 1. List Active Stories ──────────────────────────────────────────────────
storyRoutes.get('/active', optionalAuth, async (c) => {
    const activeStories = await db
        .select()
        .from(stories)
        .where(gt(stories.expiresAt, new Date()))
        .orderBy(desc(stories.createdAt));
    return c.json({ success: true, data: activeStories });
});
// ── 2. Create Story ─────────────────────────────────────────────────────────
const createStorySchema = z.object({
    imageUrl: z.string().default(''),
    videoUrl: z.string().optional(),
    videoTrimStartMs: z.number().optional(),
    videoTrimEndMs: z.number().optional(),
    textContent: z.string().optional(),
    backgroundColor: z.number().optional(),
    textColor: z.number().optional(),
    textBorderStyle: z.string().optional(),
    sharedPostId: z.string().optional(),
    sharedEventId: z.string().optional(),
    sharedEventTitle: z.string().optional(),
    overlays: z.array(z.record(z.unknown())).default([]),
});
storyRoutes.post('/', requireAuth, zValidator('json', createStorySchema), async (c) => {
    const uid = c.get('uid');
    const body = c.req.valid('json');
    const [author] = await db.select().from(users).where(eq(users.id, uid)).limit(1);
    const storyId = `st_${randomBytes(12).toString('hex')}`;
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24-hour TTL
    await db
        .insert(stories)
        .values({
        id: storyId,
        authorUid: uid,
        authorUsername: author?.username || 'user',
        authorAvatar: author?.avatarUrl || null,
        imageUrl: body.imageUrl,
        videoUrl: body.videoUrl || null,
        videoTrimStartMs: body.videoTrimStartMs || null,
        videoTrimEndMs: body.videoTrimEndMs || null,
        textContent: body.textContent || null,
        backgroundColor: body.backgroundColor || null,
        textColor: body.textColor || null,
        textBorderStyle: body.textBorderStyle || null,
        sharedPostId: body.sharedPostId || null,
        sharedEventId: body.sharedEventId || null,
        sharedEventTitle: body.sharedEventTitle || null,
        overlays: body.overlays,
        expiresAt,
    });
    const [newStory] = await db.select().from(stories).where(eq(stories.id, storyId)).limit(1);
    return c.json({ success: true, data: newStory }, 201);
});
// ── 3. Record Story View ────────────────────────────────────────────────────
storyRoutes.post('/:id/view', requireAuth, async (c) => {
    const storyId = c.req.param('id');
    const viewerUid = c.get('uid');
    const [story] = await db.select().from(stories).where(eq(stories.id, storyId)).limit(1);
    if (!story)
        throw new AppError('Story not found', 404, 'NOT_FOUND');
    if (story.authorUid === viewerUid) {
        return c.json({ success: true, recorded: false });
    }
    const [viewerUser] = await db.select().from(users).where(eq(users.id, viewerUid)).limit(1);
    const viewerId = `${storyId}_${viewerUid}`;
    await db
        .insert(storyViewers)
        .ignore()
        .values({
        id: viewerId,
        storyId,
        uid: viewerUid,
        username: viewerUser?.username || 'user',
        avatarUrl: viewerUser?.avatarUrl || null,
    });
    return c.json({ success: true, recorded: true });
});
// ── 4. Get Story Viewers List ───────────────────────────────────────────────
storyRoutes.get('/:id/viewers', requireAuth, async (c) => {
    const storyId = c.req.param('id');
    const uid = c.get('uid');
    const [story] = await db.select().from(stories).where(eq(stories.id, storyId)).limit(1);
    if (!story)
        throw new AppError('Story not found', 404, 'NOT_FOUND');
    if (story.authorUid !== uid)
        throw new AppError('Only the story author can see viewers', 403, 'FORBIDDEN');
    const viewers = await db
        .select()
        .from(storyViewers)
        .where(eq(storyViewers.storyId, storyId))
        .orderBy(desc(storyViewers.viewedAt));
    return c.json({ success: true, data: viewers });
});
// ── 5. Toggle Story Like ────────────────────────────────────────────────────
storyRoutes.post('/:id/like', requireAuth, async (c) => {
    const storyId = c.req.param('id');
    const uid = c.get('uid');
    const [story] = await db.select().from(stories).where(eq(stories.id, storyId)).limit(1);
    if (!story)
        throw new AppError('Story not found', 404, 'NOT_FOUND');
    const likeId = `${storyId}_${uid}`;
    const [like] = await db.select().from(storyLikes).where(eq(storyLikes.id, likeId)).limit(1);
    let liked = false;
    if (like) {
        await db.delete(storyLikes).where(eq(storyLikes.id, likeId));
        await db.update(stories).set({ likesCount: sql `GREATEST(${stories.likesCount} - 1, 0)` }).where(eq(stories.id, storyId));
        liked = false;
    }
    else {
        await db.insert(storyLikes).values({ id: likeId, storyId, uid });
        await db.update(stories).set({ likesCount: sql `${stories.likesCount} + 1` }).where(eq(stories.id, storyId));
        liked = true;
    }
    return c.json({ success: true, liked });
});
// ── 6. Delete Story ─────────────────────────────────────────────────────────
storyRoutes.delete('/:id', requireAuth, async (c) => {
    const storyId = c.req.param('id');
    const uid = c.get('uid');
    const user = c.get('user');
    const [story] = await db.select().from(stories).where(eq(stories.id, storyId)).limit(1);
    if (!story)
        throw new AppError('Story not found', 404, 'NOT_FOUND');
    if (story.authorUid !== uid && user.role !== 'admin') {
        throw new AppError('Permission denied', 403, 'FORBIDDEN');
    }
    await db.delete(stories).where(eq(stories.id, storyId));
    return c.json({ success: true, message: 'Story deleted' });
});
