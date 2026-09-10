import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import { db } from '../db/index.js';
import { comments, commentLikes, commentHelpfulVotes, posts, users } from '../db/schema/index.js';
import { eq, and, sql, desc, asc, inArray } from 'drizzle-orm';
import { AppError } from '../middleware/error-handler.js';
import { requireAuth, optionalAuth } from '../middleware/auth.js';
import { findProfanityMatches } from '../services/profanity.service.js';
import { sendPushNotification } from '../services/fcm.service.js';
import { randomBytes } from 'crypto';
export const commentRoutes = new Hono();
// ── 1. List Comments for Post ───────────────────────────────────────────────
commentRoutes.get('/post/:postId', optionalAuth, async (c) => {
    const postId = c.req.param('postId');
    const viewerUid = c.get('uid');
    const postComments = await db
        .select()
        .from(comments)
        .where(and(eq(comments.postId, postId), eq(comments.senderOnly, false)))
        .orderBy(desc(comments.markedHelpful), asc(comments.createdAt));
    let likedCommentIds = new Set();
    let userVotes = new Map();
    if (viewerUid && postComments.length > 0) {
        const commentIds = postComments.map((cm) => cm.id);
        const [likes, votes] = await Promise.all([
            db.select({ commentId: commentLikes.commentId }).from(commentLikes).where(and(eq(commentLikes.uid, viewerUid), inArray(commentLikes.commentId, commentIds))),
            db.select({ commentId: commentHelpfulVotes.commentId, isHelpful: commentHelpfulVotes.isHelpful }).from(commentHelpfulVotes).where(and(eq(commentHelpfulVotes.uid, viewerUid), inArray(commentHelpfulVotes.commentId, commentIds))),
        ]);
        likedCommentIds = new Set(likes.map((l) => l.commentId));
        votes.forEach((v) => userVotes.set(v.commentId, v.isHelpful));
    }
    const enriched = postComments.map((cm) => ({
        ...cm,
        isLiked: likedCommentIds.has(cm.id),
        userVote: userVotes.has(cm.id) ? (userVotes.get(cm.id) ? 'helpful' : 'unhelpful') : null,
    }));
    return c.json({ success: true, data: enriched });
});
// ── 2. Create Comment / Reply ───────────────────────────────────────────────
const createCommentSchema = z.object({
    text: z.string().min(1).max(2000),
    parentCommentId: z.string().optional(),
    replyToUsername: z.string().optional(),
});
commentRoutes.post('/post/:postId', requireAuth, zValidator('json', createCommentSchema), async (c) => {
    const postId = c.req.param('postId');
    const uid = c.get('uid');
    const { text, parentCommentId, replyToUsername } = c.req.valid('json');
    const [post] = await db.select().from(posts).where(eq(posts.id, postId)).limit(1);
    if (!post)
        throw new AppError('Post not found', 404, 'NOT_FOUND');
    const [author] = await db.select().from(users).where(eq(users.id, uid)).limit(1);
    // Check profanity
    const matches = await findProfanityMatches(text);
    const isProfane = matches.length > 0;
    const commentId = `cm_${randomBytes(12).toString('hex')}`;
    const [newComment] = await db
        .insert(comments)
        .values({
        id: commentId,
        postId,
        authorUid: uid,
        authorUsername: author?.username || 'user',
        authorAvatar: author?.avatarUrl || null,
        text,
        parentCommentId: parentCommentId || null,
        replyToUsername: replyToUsername || null,
        profanityFiltered: isProfane,
        senderOnly: isProfane, // If profane, visible only to sender
    })
        .returning();
    if (!isProfane) {
        await db.update(posts).set({ commentsCount: sql `${posts.commentsCount} + 1` }).where(eq(posts.id, postId));
        // Notify post author or parent comment author
        const targetRecipientUid = parentCommentId
            ? (await db.select({ authorUid: comments.authorUid }).from(comments).where(eq(comments.id, parentCommentId)).limit(1))[0]?.authorUid
            : post.authorUid;
        if (targetRecipientUid && targetRecipientUid !== uid) {
            const notifType = post.postType === 'qa' ? (parentCommentId ? 'qa_reply' : 'qa_answer') : (parentCommentId ? 'reply' : 'comment');
            await sendPushNotification({
                targetUid: targetRecipientUid,
                title: post.postType === 'qa' ? 'New answer' : 'New comment',
                body: `${author?.username || 'Someone'} ${parentCommentId ? 'replied to your comment' : 'commented on your post'}`,
                type: notifType,
                actorUid: uid,
                targetId: postId,
                commentId,
            });
        }
    }
    return c.json({ success: true, data: newComment }, 201);
});
// ── 3. Edit Comment ─────────────────────────────────────────────────────────
const editCommentSchema = z.object({
    text: z.string().min(1).max(2000),
});
commentRoutes.patch('/:id', requireAuth, zValidator('json', editCommentSchema), async (c) => {
    const commentId = c.req.param('id');
    const uid = c.get('uid');
    const { text } = c.req.valid('json');
    const [existing] = await db.select().from(comments).where(eq(comments.id, commentId)).limit(1);
    if (!existing)
        throw new AppError('Comment not found', 404, 'NOT_FOUND');
    if (existing.authorUid !== uid)
        throw new AppError('Permission denied', 403, 'FORBIDDEN');
    const matches = await findProfanityMatches(text);
    if (matches.length > 0) {
        throw new AppError('Edited comment contains inappropriate words', 400, 'PROFANITY_BLOCKED');
    }
    const [updated] = await db
        .update(comments)
        .set({ text, updatedAt: new Date() })
        .where(eq(comments.id, commentId))
        .returning();
    return c.json({ success: true, data: updated });
});
// ── 4. Delete Comment ───────────────────────────────────────────────────────
commentRoutes.delete('/:id', requireAuth, async (c) => {
    const commentId = c.req.param('id');
    const uid = c.get('uid');
    const user = c.get('user');
    const [existing] = await db.select().from(comments).where(eq(comments.id, commentId)).limit(1);
    if (!existing)
        throw new AppError('Comment not found', 404, 'NOT_FOUND');
    if (existing.authorUid !== uid && user.role !== 'admin') {
        throw new AppError('Permission denied', 403, 'FORBIDDEN');
    }
    await db.delete(comments).where(eq(comments.id, commentId));
    await db.update(posts).set({ commentsCount: sql `GREATEST(${posts.commentsCount} - 1, 0)` }).where(eq(posts.id, existing.postId));
    return c.json({ success: true, message: 'Comment deleted' });
});
// ── 5. Toggle Comment Like ──────────────────────────────────────────────────
commentRoutes.post('/:id/like', requireAuth, async (c) => {
    const commentId = c.req.param('id');
    const uid = c.get('uid');
    const [existing] = await db.select().from(comments).where(eq(comments.id, commentId)).limit(1);
    if (!existing)
        throw new AppError('Comment not found', 404, 'NOT_FOUND');
    const likeId = `${commentId}_${uid}`;
    const [like] = await db.select().from(commentLikes).where(eq(commentLikes.id, likeId)).limit(1);
    let liked = false;
    if (like) {
        await db.delete(commentLikes).where(eq(commentLikes.id, likeId));
        await db.update(comments).set({ likesCount: sql `GREATEST(${comments.likesCount} - 1, 0)` }).where(eq(comments.id, commentId));
        liked = false;
    }
    else {
        await db.insert(commentLikes).values({ id: likeId, commentId, uid });
        await db.update(comments).set({ likesCount: sql `${comments.likesCount} + 1` }).where(eq(comments.id, commentId));
        liked = true;
    }
    return c.json({ success: true, liked });
});
// ── 6. Vote Helpful / Unhelpful on QA Answer ────────────────────────────────
const voteHelpfulSchema = z.object({
    isHelpful: z.boolean(),
});
commentRoutes.post('/:id/vote-helpful', requireAuth, zValidator('json', voteHelpfulSchema), async (c) => {
    const commentId = c.req.param('id');
    const uid = c.get('uid');
    const { isHelpful } = c.req.valid('json');
    const [comment] = await db.select().from(comments).where(eq(comments.id, commentId)).limit(1);
    if (!comment)
        throw new AppError('Comment not found', 404, 'NOT_FOUND');
    const voteId = `${commentId}_${uid}`;
    const [existingVote] = await db.select().from(commentHelpfulVotes).where(eq(commentHelpfulVotes.id, voteId)).limit(1);
    if (existingVote) {
        if (existingVote.isHelpful === isHelpful) {
            // Remove vote
            await db.delete(commentHelpfulVotes).where(eq(commentHelpfulVotes.id, voteId));
            if (isHelpful) {
                await db.update(comments).set({ helpfulCount: sql `GREATEST(${comments.helpfulCount} - 1, 0)` }).where(eq(comments.id, commentId));
            }
            else {
                await db.update(comments).set({ unhelpfulCount: sql `GREATEST(${comments.unhelpfulCount} - 1, 0)` }).where(eq(comments.id, commentId));
            }
            return c.json({ success: true, vote: null });
        }
        else {
            // Switch vote
            await db.update(commentHelpfulVotes).set({ isHelpful }).where(eq(commentHelpfulVotes.id, voteId));
            if (isHelpful) {
                await db.update(comments).set({
                    helpfulCount: sql `${comments.helpfulCount} + 1`,
                    unhelpfulCount: sql `GREATEST(${comments.unhelpfulCount} - 1, 0)`,
                }).where(eq(comments.id, commentId));
            }
            else {
                await db.update(comments).set({
                    unhelpfulCount: sql `${comments.unhelpfulCount} + 1`,
                    helpfulCount: sql `GREATEST(${comments.helpfulCount} - 1, 0)`,
                }).where(eq(comments.id, commentId));
            }
            return c.json({ success: true, vote: isHelpful ? 'helpful' : 'unhelpful' });
        }
    }
    else {
        await db.insert(commentHelpfulVotes).values({ id: voteId, commentId, uid, isHelpful });
        if (isHelpful) {
            await db.update(comments).set({ helpfulCount: sql `${comments.helpfulCount} + 1` }).where(eq(comments.id, commentId));
        }
        else {
            await db.update(comments).set({ unhelpfulCount: sql `${comments.unhelpfulCount} + 1` }).where(eq(comments.id, commentId));
        }
        return c.json({ success: true, vote: isHelpful ? 'helpful' : 'unhelpful' });
    }
});
// ── 7. Mark as Helpful by Question Author ───────────────────────────────────
commentRoutes.post('/:id/mark-helpful', requireAuth, async (c) => {
    const commentId = c.req.param('id');
    const uid = c.get('uid');
    const [comment] = await db.select().from(comments).where(eq(comments.id, commentId)).limit(1);
    if (!comment)
        throw new AppError('Comment not found', 404, 'NOT_FOUND');
    const [post] = await db.select().from(posts).where(eq(posts.id, comment.postId)).limit(1);
    if (!post)
        throw new AppError('Post not found', 404, 'NOT_FOUND');
    if (post.authorUid !== uid) {
        throw new AppError('Only the question author can mark answers as verified helpful', 403, 'FORBIDDEN');
    }
    const newMarked = !comment.markedHelpful;
    await db.update(comments).set({ markedHelpful: newMarked }).where(eq(comments.id, commentId));
    return c.json({ success: true, markedHelpful: newMarked });
});
