import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import { db } from '../db/index.js';
import { posts, postLikes, postReposts, postSaves, postReports, users, comments, notifications, follows } from '../db/schema/index.js';
import { eq, and, sql, desc, inArray } from 'drizzle-orm';
import { AppError } from '../middleware/error-handler.js';
import { requireAuth, optionalAuth } from '../middleware/auth.js';
import { findProfanityMatches } from '../services/profanity.service.js';
import { sendPushNotification } from '../services/fcm.service.js';
import { randomBytes } from 'crypto';
export const postRoutes = new Hono();
function extractMentions(text) {
    const matches = text.match(/@([a-zA-Z0-9_]{3,30})/g);
    if (!matches)
        return [];
    return Array.from(new Set(matches.map((m) => m.substring(1).toLowerCase())));
}
// ── 1. Stream / List Main Feed (Excludes Q&A) ────────────────────────────────
postRoutes.get('/', optionalAuth, async (c) => {
    const viewerUid = c.get('uid');
    const limit = Math.min(Number(c.req.query('limit')) || 30, 100);
    const cursor = c.req.query('cursor');
    const authorUid = c.req.query('authorUid');
    const type = c.req.query('type'); // 'regular' | 'qa' | 'all'
    const saved = c.req.query('saved'); // 'true'
    const repostedBy = c.req.query('repostedBy');
    const answeredBy = c.req.query('answeredBy');
    const conditions = [];
    // 1. Author Filter (e.g. User Profile Page)
    if (authorUid) {
        conditions.push(eq(posts.authorUid, authorUid));
        // Privacy check: Viewer sees private posts if viewer is author, or follows author actively
        if (viewerUid && viewerUid !== authorUid) {
            const [follow] = await db
                .select()
                .from(follows)
                .where(and(eq(follows.followerUid, viewerUid), eq(follows.targetUid, authorUid), eq(follows.status, 'active')))
                .limit(1);
            if (!follow) {
                conditions.push(eq(posts.isPrivate, false));
            }
        }
        else if (!viewerUid) {
            conditions.push(eq(posts.isPrivate, false));
        }
    }
    // 2. Saved Posts Tab
    if (saved === 'true') {
        if (!viewerUid)
            return c.json({ success: true, data: [] });
        const savedPostIds = await db
            .select({ postId: postSaves.postId })
            .from(postSaves)
            .where(eq(postSaves.uid, viewerUid));
        const ids = savedPostIds.map((r) => r.postId);
        if (ids.length === 0)
            return c.json({ success: true, data: [] });
        conditions.push(inArray(posts.id, ids));
    }
    // 3. Reposted Posts Tab
    if (repostedBy) {
        const repostedPostIds = await db
            .select({ postId: postReposts.postId })
            .from(postReposts)
            .where(eq(postReposts.uid, repostedBy));
        const ids = repostedPostIds.map((r) => r.postId);
        if (ids.length === 0)
            return c.json({ success: true, data: [] });
        conditions.push(inArray(posts.id, ids));
    }
    // 4. QA Answered By Tab
    if (answeredBy) {
        const answeredPostIds = await db
            .select({ postId: comments.postId })
            .from(comments)
            .where(eq(comments.authorUid, answeredBy));
        const ids = Array.from(new Set(answeredPostIds.map((r) => r.postId)));
        if (ids.length === 0)
            return c.json({ success: true, data: [] });
        conditions.push(inArray(posts.id, ids));
        conditions.push(eq(posts.postType, 'qa'));
    }
    // 5. Post Type Filter
    if (type === 'qa') {
        conditions.push(eq(posts.postType, 'qa'));
    }
    else if (type === 'regular') {
        conditions.push(eq(posts.postType, 'regular'));
    }
    else if (!type && !saved && !repostedBy && !answeredBy) {
        conditions.push(eq(posts.postType, 'regular'));
    }
    // 6. Global Feed Privacy
    if (!authorUid && saved !== 'true') {
        conditions.push(eq(posts.isPrivate, false));
    }
    // 7. Cursor Pagination
    if (cursor) {
        conditions.push(sql `${posts.createdAt} < ${new Date(cursor)}`);
    }
    const feedPosts = await db
        .select()
        .from(posts)
        .where(conditions.length > 0 ? and(...conditions) : sql `1=1`)
        .orderBy(desc(posts.createdAt))
        .limit(limit);
    // If viewer signed in, enrich with liked/saved/reposted flags
    let likedSet = new Set();
    let savedSet = new Set();
    let repostedSet = new Set();
    if (viewerUid && feedPosts.length > 0) {
        const postIds = feedPosts.map((p) => p.id);
        const [likesResult, savesResult, repostsResult] = await Promise.all([
            db.select({ postId: postLikes.postId }).from(postLikes).where(and(eq(postLikes.uid, viewerUid), inArray(postLikes.postId, postIds))),
            db.select({ postId: postSaves.postId }).from(postSaves).where(and(eq(postSaves.uid, viewerUid), inArray(postSaves.postId, postIds))),
            db.select({ postId: postReposts.postId }).from(postReposts).where(and(eq(postReposts.uid, viewerUid), inArray(postReposts.postId, postIds))),
        ]);
        likedSet = new Set(likesResult.map((r) => r.postId));
        savedSet = new Set(savesResult.map((r) => r.postId));
        repostedSet = new Set(repostsResult.map((r) => r.postId));
    }
    const enriched = feedPosts.map((post) => ({
        ...post,
        isLiked: likedSet.has(post.id),
        isSaved: savedSet.has(post.id),
        isReposted: repostedSet.has(post.id),
    }));
    return c.json({ success: true, data: enriched });
});
// ── 2. Stream / List Q&A Feed ───────────────────────────────────────────────
postRoutes.get('/qa', optionalAuth, async (c) => {
    const viewerUid = c.get('uid');
    const limit = Math.min(Number(c.req.query('limit')) || 50, 100);
    const qaPosts = await db
        .select()
        .from(posts)
        .where(eq(posts.postType, 'qa'))
        .orderBy(desc(posts.createdAt))
        .limit(limit);
    return c.json({ success: true, data: qaPosts });
});
// ── 3. Get Single Post by ID ────────────────────────────────────────────────
postRoutes.get('/:id', optionalAuth, async (c) => {
    const postId = c.req.param('id');
    const viewerUid = c.get('uid');
    const [post] = await db.select().from(posts).where(eq(posts.id, postId)).limit(1);
    if (!post)
        throw new AppError('Post not found', 404, 'NOT_FOUND');
    let isLiked = false;
    let isSaved = false;
    let isReposted = false;
    if (viewerUid) {
        const [like] = await db.select().from(postLikes).where(and(eq(postLikes.postId, postId), eq(postLikes.uid, viewerUid))).limit(1);
        const [save] = await db.select().from(postSaves).where(and(eq(postSaves.postId, postId), eq(postSaves.uid, viewerUid))).limit(1);
        const [repost] = await db.select().from(postReposts).where(and(eq(postReposts.postId, postId), eq(postReposts.uid, viewerUid))).limit(1);
        isLiked = Boolean(like);
        isSaved = Boolean(save);
        isReposted = Boolean(repost);
    }
    return c.json({
        success: true,
        data: {
            ...post,
            isLiked,
            isSaved,
            isReposted,
        },
    });
});
// ── 4. Create Post ──────────────────────────────────────────────────────────
const createPostSchema = z.object({
    caption: z.string(),
    imageUrls: z.array(z.string()).default([]),
    videoUrls: z.array(z.string()).default([]),
    isPrivate: z.boolean().default(false),
    postPlaceName: z.string().optional(),
    postPlaceCity: z.string().optional(),
    postLat: z.number().optional(),
    postLng: z.number().optional(),
    postLocationExact: z.boolean().default(false),
    metadata: z.record(z.unknown()).optional(),
});
postRoutes.post('/', requireAuth, zValidator('json', createPostSchema), async (c) => {
    const uid = c.get('uid');
    const body = c.req.valid('json');
    // Check profanity
    const checkText = [body.caption, body.postPlaceName, body.postPlaceCity].filter(Boolean).join(' ');
    const matches = await findProfanityMatches(checkText);
    if (matches.length > 0) {
        throw new AppError('This post contains blocked words and cannot be published', 400, 'PROFANITY_BLOCKED', { matches });
    }
    const [author] = await db.select().from(users).where(eq(users.id, uid)).limit(1);
    const postId = `pst_${randomBytes(12).toString('hex')}`;
    const placeSearch = [body.postPlaceName, body.postPlaceCity].filter(Boolean).join(' ').toLowerCase();
    await db
        .insert(posts)
        .values({
        id: postId,
        authorUid: uid,
        authorUsername: author?.username || 'user',
        authorAvatar: author?.avatarUrl || null,
        caption: body.caption,
        imageUrls: body.imageUrls,
        videoUrls: body.videoUrls,
        isPrivate: body.isPrivate,
        postType: 'regular',
        postPlaceName: body.postPlaceName || null,
        postPlaceCity: body.postPlaceCity || null,
        postLat: body.postLat || null,
        postLng: body.postLng || null,
        postLocationExact: body.postLocationExact,
        placeSearchKey: placeSearch || null,
        metadata: body.metadata || {},
    });
    const [newPost] = await db.select().from(posts).where(eq(posts.id, postId)).limit(1);
    // Increment user's posts count
    await db.update(users).set({ postsCount: sql `${users.postsCount} + 1` }).where(eq(users.id, uid));
    // Process @mentions
    const mentionedUsernames = extractMentions(body.caption);
    if (mentionedUsernames.length > 0) {
        const targets = await db.select({ id: users.id }).from(users).where(inArray(users.usernameLower, mentionedUsernames));
        for (const target of targets) {
            if (target.id === uid)
                continue;
            await db.insert(notifications).ignore().values({
                id: `mention_${postId}_${target.id}`,
                targetUid: target.id,
                actorUid: uid,
                type: 'mention',
                targetId: postId,
            });
            await sendPushNotification({
                targetUid: target.id,
                title: 'New mention',
                body: `${author?.username || 'Someone'} mentioned you in a post`,
                type: 'mention',
                actorUid: uid,
                targetId: postId,
            });
        }
    }
    return c.json({ success: true, data: newPost }, 201);
});
// ── 5. Create Q&A Post / Discussion ─────────────────────────────────────────
const createQaSchema = z.object({
    question: z.string().min(3),
    details: z.string().optional(),
    discussKind: z.enum(['question', 'discussion']).default('question'),
    sourcePostId: z.string().optional(),
});
postRoutes.post('/qa', requireAuth, zValidator('json', createQaSchema), async (c) => {
    const uid = c.get('uid');
    const { question, details, discussKind, sourcePostId } = c.req.valid('json');
    const caption = details?.trim() ? `${question.trim()}\n${details.trim()}` : question.trim();
    const matches = await findProfanityMatches(caption);
    if (matches.length > 0) {
        throw new AppError('This discuss question contains blocked words and cannot be posted', 400, 'PROFANITY_BLOCKED', { matches });
    }
    const [author] = await db.select().from(users).where(eq(users.id, uid)).limit(1);
    const postId = `qa_${randomBytes(12).toString('hex')}`;
    await db
        .insert(posts)
        .values({
        id: postId,
        authorUid: uid,
        authorUsername: author?.username || 'user',
        authorAvatar: author?.avatarUrl || null,
        caption,
        imageUrls: [],
        videoUrls: [],
        postType: 'qa',
        discussKind,
        sourcePostId: sourcePostId || null,
    });
    const [qaPost] = await db.select().from(posts).where(eq(posts.id, postId)).limit(1);
    return c.json({ success: true, data: qaPost }, 201);
});
// ── 6. Delete Post ──────────────────────────────────────────────────────────
postRoutes.delete('/:id', requireAuth, async (c) => {
    const postId = c.req.param('id');
    const uid = c.get('uid');
    const user = c.get('user');
    const [post] = await db.select().from(posts).where(eq(posts.id, postId)).limit(1);
    if (!post)
        throw new AppError('Post not found', 404, 'NOT_FOUND');
    if (post.authorUid !== uid && user.role !== 'admin') {
        throw new AppError('Permission denied', 403, 'FORBIDDEN');
    }
    await db.delete(posts).where(eq(posts.id, postId));
    if (post.postType === 'regular') {
        await db.update(users).set({ postsCount: sql `GREATEST(${users.postsCount} - 1, 0)` }).where(eq(users.id, post.authorUid));
    }
    return c.json({ success: true, message: 'Post deleted' });
});
// ── 7. Toggle Like ──────────────────────────────────────────────────────────
postRoutes.post('/:id/like', requireAuth, async (c) => {
    const postId = c.req.param('id');
    const uid = c.get('uid');
    const [post] = await db.select().from(posts).where(eq(posts.id, postId)).limit(1);
    if (!post)
        throw new AppError('Post not found', 404, 'NOT_FOUND');
    const likeId = `${postId}_${uid}`;
    const [existing] = await db.select().from(postLikes).where(eq(postLikes.id, likeId)).limit(1);
    let liked = false;
    if (existing) {
        await db.delete(postLikes).where(eq(postLikes.id, likeId));
        await db.update(posts).set({ likesCount: sql `GREATEST(${posts.likesCount} - 1, 0)` }).where(eq(posts.id, postId));
        liked = false;
    }
    else {
        await db.insert(postLikes).values({ id: likeId, postId, uid });
        await db.update(posts).set({ likesCount: sql `${posts.likesCount} + 1` }).where(eq(posts.id, postId));
        liked = true;
        if (post.authorUid !== uid) {
            const [actor] = await db.select().from(users).where(eq(users.id, uid)).limit(1);
            await sendPushNotification({
                targetUid: post.authorUid,
                title: 'New like',
                body: `${actor?.username || 'Someone'} liked your post`,
                type: 'like',
                actorUid: uid,
                targetId: postId,
            });
        }
    }
    return c.json({ success: true, liked });
});
// ── 8. Toggle Repost ────────────────────────────────────────────────────────
postRoutes.post('/:id/repost', requireAuth, async (c) => {
    const postId = c.req.param('id');
    const uid = c.get('uid');
    const [post] = await db.select().from(posts).where(eq(posts.id, postId)).limit(1);
    if (!post)
        throw new AppError('Post not found', 404, 'NOT_FOUND');
    const repostId = `${postId}_${uid}`;
    const [existing] = await db.select().from(postReposts).where(eq(postReposts.id, repostId)).limit(1);
    let reposted = false;
    if (existing) {
        await db.delete(postReposts).where(eq(postReposts.id, repostId));
        reposted = false;
    }
    else {
        await db.insert(postReposts).values({ id: repostId, postId, uid });
        reposted = true;
    }
    return c.json({ success: true, reposted });
});
// ── 9. Toggle Save / Bookmark ───────────────────────────────────────────────
postRoutes.post('/:id/save', requireAuth, async (c) => {
    const postId = c.req.param('id');
    const uid = c.get('uid');
    const [post] = await db.select().from(posts).where(eq(posts.id, postId)).limit(1);
    if (!post)
        throw new AppError('Post not found', 404, 'NOT_FOUND');
    const saveId = `${postId}_${uid}`;
    const [existing] = await db.select().from(postSaves).where(eq(postSaves.id, saveId)).limit(1);
    let saved = false;
    if (existing) {
        await db.delete(postSaves).where(eq(postSaves.id, saveId));
        saved = false;
    }
    else {
        await db.insert(postSaves).values({ id: saveId, postId, uid });
        saved = true;
    }
    return c.json({ success: true, saved });
});
// ── 10. Report Post ─────────────────────────────────────────────────────────
const reportPostSchema = z.object({
    reason: z.string().min(1),
    details: z.string().optional(),
});
postRoutes.post('/:id/report', requireAuth, zValidator('json', reportPostSchema), async (c) => {
    const postId = c.req.param('id');
    const reporterUid = c.get('uid');
    const { reason, details } = c.req.valid('json');
    const [post] = await db.select().from(posts).where(eq(posts.id, postId)).limit(1);
    if (!post)
        throw new AppError('Post not found', 404, 'NOT_FOUND');
    if (post.authorUid === reporterUid) {
        throw new AppError('You cannot report your own content', 400, 'CANNOT_REPORT_SELF');
    }
    const [reporter] = await db.select().from(users).where(eq(users.id, reporterUid)).limit(1);
    const reportId = `${postId}_${reporterUid}`;
    await db.insert(postReports).ignore().values({
        id: reportId,
        postId,
        postAuthorUid: post.authorUid,
        postAuthorUsername: post.authorUsername,
        postAuthorAvatar: post.authorAvatar,
        postCaption: post.caption,
        reporterUid,
        reporterUsername: reporter?.username || 'user',
        reason,
        details: details?.trim() || null,
        isQa: post.postType === 'qa',
    });
    return c.json({ success: true, message: 'Report submitted successfully' });
});
