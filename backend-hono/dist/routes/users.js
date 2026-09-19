import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import { db } from '../db/index.js';
import { users, follows, blocks, profileVisitors, userReports, notifications, chats, contactRequests, errorReports } from '../db/schema/index.js';
import { randomBytes } from 'crypto';
import { eq, and, sql, desc, inArray } from 'drizzle-orm';
import { AppError } from '../middleware/error-handler.js';
import { requireAuth, optionalAuth } from '../middleware/auth.js';
import { sendPushNotification } from '../services/fcm.service.js';
import { normalizeMediaUrl } from '../utils/url.js';
export const userRoutes = new Hono();
export function formatUser(user) {
    return {
        ...user,
        avatarUrl: normalizeMediaUrl(user.avatarUrl),
        coverUrl: normalizeMediaUrl(user.coverUrl),
    };
}
// ── 1. Check Username Availability ──────────────────────────────────────────
userRoutes.get('/check-username', async (c) => {
    const username = c.req.query('username')?.trim().toLowerCase();
    const excludeUid = c.req.query('excludeUid');
    if (!username) {
        return c.json({ success: true, available: false });
    }
    const matches = await db
        .select({ id: users.id })
        .from(users)
        .where(eq(users.usernameLower, username))
        .limit(1);
    const available = matches.length === 0 || (excludeUid && matches[0].id === excludeUid);
    return c.json({ success: true, available: Boolean(available) });
});
// ── 2. Batch Resolve Usernames to UIDs (for @mentions) ──────────────────────
const resolveMentionsSchema = z.object({
    usernames: z.array(z.string()),
});
userRoutes.post('/resolve-usernames', zValidator('json', resolveMentionsSchema), async (c) => {
    const { usernames } = c.req.valid('json');
    if (usernames.length === 0) {
        return c.json({ success: true, data: {} });
    }
    const normalized = usernames.map((u) => u.trim().toLowerCase());
    const found = await db
        .select({ id: users.id, usernameLower: users.usernameLower })
        .from(users)
        .where(inArray(users.usernameLower, normalized));
    const result = {};
    for (const row of found) {
        if (row.usernameLower) {
            result[row.usernameLower] = row.id;
        }
    }
    return c.json({ success: true, data: result });
});
// ── 3. Get Current User Profile ─────────────────────────────────────────────
userRoutes.get('/me', requireAuth, async (c) => {
    const uid = c.get('uid');
    const [user] = await db.select().from(users).where(eq(users.id, uid)).limit(1);
    if (!user) {
        throw new AppError('User not found', 404, 'NOT_FOUND');
    }
    return c.json({ success: true, data: formatUser(user) });
});
// ── 4. Update Current User Profile ──────────────────────────────────────────
const updateProfileSchema = z.object({
    username: z.string().min(3).max(30).optional(),
    bio: z.string().max(500).optional(),
    avatarUrl: z.string().nullable().optional(),
    coverUrl: z.string().nullable().optional(),
    gender: z.string().nullable().optional(),
    isPrivate: z.boolean().optional(),
    appIntroSeen: z.boolean().optional(),
    profession: z.string().nullable().optional(),
    field: z.string().nullable().optional(),
    academicLevel: z.string().nullable().optional(),
    goals: z.array(z.string()).optional(),
    eventNotifPrefs: z.object({
        mode: z.enum(['all', 'off']),
        types: z.array(z.string()),
        countries: z.array(z.string()),
    }).optional(),
    metadata: z.record(z.unknown()).optional(),
});
userRoutes.patch('/me', requireAuth, zValidator('json', updateProfileSchema), async (c) => {
    const uid = c.get('uid');
    const body = c.req.valid('json');
    const patch = {
        updatedAt: new Date(),
    };
    if (body.username !== undefined) {
        const normalized = body.username.trim().toLowerCase();
        const collision = await db
            .select({ id: users.id })
            .from(users)
            .where(and(eq(users.usernameLower, normalized), sql `${users.id} != ${uid}`))
            .limit(1);
        if (collision.length > 0) {
            throw new AppError('This username is already taken', 409, 'USERNAME_TAKEN');
        }
        patch.username = body.username.trim();
        patch.usernameLower = normalized;
        patch.handle = `@${body.username.trim()}`;
    }
    if (body.bio !== undefined)
        patch.bio = body.bio;
    if (body.avatarUrl !== undefined)
        patch.avatarUrl = body.avatarUrl;
    if (body.coverUrl !== undefined)
        patch.coverUrl = body.coverUrl;
    if (body.gender !== undefined)
        patch.gender = body.gender;
    if (body.isPrivate !== undefined)
        patch.isPrivate = body.isPrivate;
    if (body.appIntroSeen !== undefined)
        patch.appIntroSeen = body.appIntroSeen;
    if (body.profession !== undefined)
        patch.profession = body.profession;
    if (body.field !== undefined)
        patch.field = body.field;
    if (body.academicLevel !== undefined)
        patch.academicLevel = body.academicLevel;
    if (body.goals !== undefined)
        patch.goals = body.goals;
    if (body.eventNotifPrefs !== undefined)
        patch.eventNotifPrefs = body.eventNotifPrefs;
    if (body.metadata !== undefined)
        patch.metadata = body.metadata;
    await db.update(users).set(patch).where(eq(users.id, uid));
    const [updated] = await db.select().from(users).where(eq(users.id, uid)).limit(1);
    return c.json({ success: true, data: updated ? formatUser(updated) : null });
});
// ── 5. Get User by UID ──────────────────────────────────────────────────────
userRoutes.get('/:uid', optionalAuth, async (c) => {
    const targetUid = c.req.param('uid');
    const viewerUid = c.get('uid');
    const [user] = await db
        .select()
        .from(users)
        .where(and(eq(users.id, targetUid), sql `${users.deletedAt} IS NULL`))
        .limit(1);
    if (!user) {
        throw new AppError('User not found', 404, 'NOT_FOUND');
    }
    let isFollowing = false;
    let isPending = false;
    let isBlocked = false;
    if (viewerUid && viewerUid !== targetUid) {
        const [followRelation] = await db
            .select()
            .from(follows)
            .where(and(eq(follows.followerUid, viewerUid), eq(follows.targetUid, targetUid)))
            .limit(1);
        if (followRelation) {
            isFollowing = followRelation.status === 'active';
            isPending = followRelation.status === 'pending';
        }
        const [blockRelation] = await db
            .select()
            .from(blocks)
            .where(and(eq(blocks.blockerUid, viewerUid), eq(blocks.blockedUid, targetUid)))
            .limit(1);
        isBlocked = Boolean(blockRelation);
    }
    return c.json({
        success: true,
        data: formatUser({
            ...user,
            isFollowing,
            isPending,
            isBlocked,
        }),
    });
});
// ── 6. Profile Visitor Recording ────────────────────────────────────────────
userRoutes.post('/:uid/visit', requireAuth, async (c) => {
    const targetUid = c.req.param('uid');
    const visitorUid = c.get('uid');
    if (targetUid === visitorUid) {
        return c.json({ success: true, recorded: false });
    }
    await db
        .insert(profileVisitors)
        .values({
        ownerUid: targetUid,
        visitorUid,
        visitCount: 1,
        lastVisitedAt: new Date(),
    })
        .onDuplicateKeyUpdate({
        set: {
            visitCount: sql `${profileVisitors.visitCount} + 1`,
            lastVisitedAt: new Date(),
        },
    });
    return c.json({ success: true, recorded: true });
});
userRoutes.get('/:uid/visitors', requireAuth, async (c) => {
    const uid = c.get('uid');
    const requestedUid = c.req.param('uid');
    if (uid !== requestedUid) {
        throw new AppError('Unauthorized access to visitor history', 403, 'FORBIDDEN');
    }
    const visitors = await db
        .select({
        uid: users.id,
        username: users.username,
        avatarUrl: users.avatarUrl,
        visitCount: profileVisitors.visitCount,
        lastVisitedAt: profileVisitors.lastVisitedAt,
    })
        .from(profileVisitors)
        .innerJoin(users, eq(profileVisitors.visitorUid, users.id))
        .where(eq(profileVisitors.ownerUid, uid))
        .orderBy(desc(profileVisitors.lastVisitedAt))
        .limit(100);
    const formattedVisitors = visitors.map((v) => ({
        ...v,
        avatarUrl: normalizeMediaUrl(v.avatarUrl),
    }));
    return c.json({ success: true, data: formattedVisitors });
});
// ── 7. Follow / Unfollow ────────────────────────────────────────────────────
userRoutes.post('/:uid/follow', requireAuth, async (c) => {
    const targetUid = c.req.param('uid');
    const followerUid = c.get('uid');
    if (targetUid === followerUid) {
        throw new AppError('You cannot follow yourself', 400, 'CANNOT_FOLLOW_SELF');
    }
    const [targetUser] = await db.select().from(users).where(eq(users.id, targetUid)).limit(1);
    if (!targetUser)
        throw new AppError('User not found', 404, 'NOT_FOUND');
    const status = targetUser.isPrivate ? 'pending' : 'active';
    const followId = `${followerUid}_${targetUid}`;
    await db.insert(follows).ignore().values({
        id: followId,
        followerUid,
        targetUid,
        status,
    });
    if (status === 'active') {
        // Increment counts
        await db.update(users).set({ followersCount: sql `${users.followersCount} + 1` }).where(eq(users.id, targetUid));
        await db.update(users).set({ followingCount: sql `${users.followingCount} + 1` }).where(eq(users.id, followerUid));
        // Promote mutual direct chat if exists
        const [reciprocal] = await db
            .select()
            .from(follows)
            .where(and(eq(follows.followerUid, targetUid), eq(follows.targetUid, followerUid), eq(follows.status, 'active')))
            .limit(1);
        if (reciprocal) {
            const sorted = [followerUid, targetUid].sort();
            const chatId = `${sorted[0]}_${sorted[1]}`;
            await db.update(chats).set({
                acceptedBy: [followerUid, targetUid]
            }).where(eq(chats.id, chatId));
        }
    }
    // Create notification
    const [followerUser] = await db.select().from(users).where(eq(users.id, followerUid)).limit(1);
    const notifType = status === 'pending' ? 'follow_request' : 'follow';
    await db.insert(notifications).ignore().values({
        id: `notif_follow_${followerUid}_${targetUid}`,
        targetUid,
        actorUid: followerUid,
        type: notifType,
        targetId: followerUid,
    });
    // Send push notification
    await sendPushNotification({
        targetUid,
        title: status === 'pending' ? 'New follow request' : 'New follower',
        body: `${followerUser?.username || 'Someone'} ${status === 'pending' ? 'requested to follow you' : 'started following you'}`,
        type: notifType,
        actorUid: followerUid,
    });
    return c.json({ success: true, status });
});
userRoutes.delete('/:uid/follow', requireAuth, async (c) => {
    const targetUid = c.req.param('uid');
    const followerUid = c.get('uid');
    const [existing] = await db
        .select()
        .from(follows)
        .where(and(eq(follows.followerUid, followerUid), eq(follows.targetUid, targetUid)))
        .limit(1);
    if (existing) {
        await db.delete(follows).where(and(eq(follows.followerUid, followerUid), eq(follows.targetUid, targetUid)));
        if (existing.status === 'active') {
            await db.update(users).set({ followersCount: sql `GREATEST(${users.followersCount} - 1, 0)` }).where(eq(users.id, targetUid));
            await db.update(users).set({ followingCount: sql `GREATEST(${users.followingCount} - 1, 0)` }).where(eq(users.id, followerUid));
        }
        await db.delete(notifications).where(and(eq(notifications.targetUid, targetUid), eq(notifications.actorUid, followerUid), inArray(notifications.type, ['follow', 'follow_request'])));
    }
    return c.json({ success: true, message: 'Unfollowed successfully' });
});
// ── 7b. Get Followers ───────────────────────────────────────────────────────
userRoutes.get('/:uid/followers', optionalAuth, async (c) => {
    const targetUid = c.req.param('uid');
    const viewerUid = c.get('uid');
    const followerRows = await db
        .select({
        id: users.id,
        username: users.username,
        handle: users.handle,
        avatarUrl: users.avatarUrl,
        bio: users.bio,
        isPrivate: users.isPrivate,
        followersCount: users.followersCount,
        followingCount: users.followingCount,
    })
        .from(follows)
        .innerJoin(users, eq(follows.followerUid, users.id))
        .where(and(eq(follows.targetUid, targetUid), eq(follows.status, 'active')));
    let viewerFollowingSet = new Set();
    if (viewerUid && followerRows.length > 0) {
        const userIds = followerRows.map((r) => r.id);
        const viewerFollows = await db
            .select({ targetUid: follows.targetUid })
            .from(follows)
            .where(and(eq(follows.followerUid, viewerUid), eq(follows.status, 'active'), inArray(follows.targetUid, userIds)));
        viewerFollowingSet = new Set(viewerFollows.map((f) => f.targetUid));
    }
    const result = followerRows.map((u) => ({
        ...u,
        avatarUrl: normalizeMediaUrl(u.avatarUrl),
        isFollowing: viewerFollowingSet.has(u.id),
    }));
    const uids = result.map((u) => u.id);
    return c.json({
        success: true,
        data: result,
        uids,
    });
});
// ── 7c. Get Following ───────────────────────────────────────────────────────
userRoutes.get('/:uid/following', optionalAuth, async (c) => {
    const targetUid = c.req.param('uid');
    const viewerUid = c.get('uid');
    const followingRows = await db
        .select({
        id: users.id,
        username: users.username,
        handle: users.handle,
        avatarUrl: users.avatarUrl,
        bio: users.bio,
        isPrivate: users.isPrivate,
        followersCount: users.followersCount,
        followingCount: users.followingCount,
    })
        .from(follows)
        .innerJoin(users, eq(follows.targetUid, users.id))
        .where(and(eq(follows.followerUid, targetUid), eq(follows.status, 'active')));
    let viewerFollowingSet = new Set();
    if (viewerUid && followingRows.length > 0) {
        const userIds = followingRows.map((r) => r.id);
        const viewerFollows = await db
            .select({ targetUid: follows.targetUid })
            .from(follows)
            .where(and(eq(follows.followerUid, viewerUid), eq(follows.status, 'active'), inArray(follows.targetUid, userIds)));
        viewerFollowingSet = new Set(viewerFollows.map((f) => f.targetUid));
    }
    const result = followingRows.map((u) => ({
        ...u,
        avatarUrl: normalizeMediaUrl(u.avatarUrl),
        isFollowing: viewerFollowingSet.has(u.id),
    }));
    const uids = result.map((u) => u.id);
    return c.json({
        success: true,
        data: result,
        uids,
    });
});
// ── 7d. Get Follow Status ───────────────────────────────────────────────────
userRoutes.get('/:uid/follow-status', requireAuth, async (c) => {
    const targetUid = c.req.param('uid');
    const viewerUid = c.get('uid');
    const [followingRel] = await db
        .select()
        .from(follows)
        .where(and(eq(follows.followerUid, viewerUid), eq(follows.targetUid, targetUid)))
        .limit(1);
    const [followerRel] = await db
        .select()
        .from(follows)
        .where(and(eq(follows.followerUid, targetUid), eq(follows.targetUid, viewerUid)))
        .limit(1);
    return c.json({
        success: true,
        data: {
            isFollowing: followingRel?.status === 'active',
            isPending: followingRel?.status === 'pending',
            isFollower: followerRel?.status === 'active',
        },
    });
});
// ── 7e. Get Follow Requests ─────────────────────────────────────────────────
userRoutes.get('/:uid/follow-requests', requireAuth, async (c) => {
    const uid = c.get('uid');
    const targetUid = c.req.param('uid');
    if (uid !== targetUid) {
        throw new AppError('Forbidden', 403, 'FORBIDDEN');
    }
    const rows = await db
        .select({ followerUid: follows.followerUid })
        .from(follows)
        .where(and(eq(follows.targetUid, uid), eq(follows.status, 'pending')))
        .orderBy(desc(follows.createdAt));
    const uids = rows.map((r) => r.followerUid);
    return c.json({ success: true, data: uids });
});
// ── 7f. Accept Follow Request ───────────────────────────────────────────────
userRoutes.post('/:uid/follow-requests/:requesterUid/accept', requireAuth, async (c) => {
    const uid = c.get('uid');
    const targetUid = c.req.param('uid');
    const requesterUid = c.req.param('requesterUid');
    if (uid !== targetUid) {
        throw new AppError('Forbidden', 403, 'FORBIDDEN');
    }
    const [request] = await db
        .select()
        .from(follows)
        .where(and(eq(follows.followerUid, requesterUid), eq(follows.targetUid, uid), eq(follows.status, 'pending')))
        .limit(1);
    if (!request) {
        throw new AppError('Follow request not found', 404, 'NOT_FOUND');
    }
    await db
        .update(follows)
        .set({ status: 'active' })
        .where(and(eq(follows.followerUid, requesterUid), eq(follows.targetUid, uid)));
    await db.update(users).set({ followersCount: sql `${users.followersCount} + 1` }).where(eq(users.id, uid));
    await db.update(users).set({ followingCount: sql `${users.followingCount} + 1` }).where(eq(users.id, requesterUid));
    // Promote mutual direct chat if exists
    const [reciprocal] = await db
        .select()
        .from(follows)
        .where(and(eq(follows.followerUid, uid), eq(follows.targetUid, requesterUid), eq(follows.status, 'active')))
        .limit(1);
    if (reciprocal) {
        const sorted = [requesterUid, uid].sort();
        const chatId = `${sorted[0]}_${sorted[1]}`;
        await db.update(chats).set({
            acceptedBy: [requesterUid, uid],
        }).where(eq(chats.id, chatId));
    }
    return c.json({ success: true, accepted: true });
});
// ── 7g. Reject Follow Request ───────────────────────────────────────────────
userRoutes.post('/:uid/follow-requests/:requesterUid/reject', requireAuth, async (c) => {
    const uid = c.get('uid');
    const targetUid = c.req.param('uid');
    const requesterUid = c.req.param('requesterUid');
    if (uid !== targetUid) {
        throw new AppError('Forbidden', 403, 'FORBIDDEN');
    }
    await db
        .delete(follows)
        .where(and(eq(follows.followerUid, requesterUid), eq(follows.targetUid, uid), eq(follows.status, 'pending')));
    return c.json({ success: true, rejected: true });
});
// ── 8. Block / Unblock ──────────────────────────────────────────────────────
userRoutes.post('/:uid/block', requireAuth, async (c) => {
    const targetUid = c.req.param('uid');
    const blockerUid = c.get('uid');
    if (targetUid === blockerUid) {
        throw new AppError('You cannot block yourself', 400, 'INVALID_ACTION');
    }
    const blockId = `${blockerUid}_${targetUid}`;
    await db.insert(blocks).ignore().values({ id: blockId, blockerUid, blockedUid: targetUid });
    // Remove follow relations in both directions
    await db.delete(follows).where(sql `(${follows.followerUid} = ${blockerUid} AND ${follows.targetUid} = ${targetUid}) OR (${follows.followerUid} = ${targetUid} AND ${follows.targetUid} = ${blockerUid})`);
    return c.json({ success: true, blocked: true });
});
userRoutes.delete('/:uid/block', requireAuth, async (c) => {
    const targetUid = c.req.param('uid');
    const blockerUid = c.get('uid');
    await db.delete(blocks).where(and(eq(blocks.blockerUid, blockerUid), eq(blocks.blockedUid, targetUid)));
    return c.json({ success: true, blocked: false });
});
// ── 9. Report User Profile ──────────────────────────────────────────────────
const reportUserSchema = z.object({
    reason: z.string().min(1),
    details: z.string().optional(),
});
userRoutes.post('/:uid/report', requireAuth, zValidator('json', reportUserSchema), async (c) => {
    const targetUid = c.req.param('uid');
    const reporterUid = c.get('uid');
    const { reason, details } = c.req.valid('json');
    if (targetUid === reporterUid) {
        throw new AppError('You cannot report your own profile', 400, 'CANNOT_REPORT_SELF');
    }
    const [target] = await db.select().from(users).where(eq(users.id, targetUid)).limit(1);
    const [reporter] = await db.select().from(users).where(eq(users.id, reporterUid)).limit(1);
    if (!target)
        throw new AppError('Target user not found', 404, 'NOT_FOUND');
    const reportId = `${targetUid}_${reporterUid}`;
    await db.insert(userReports).ignore().values({
        id: reportId,
        targetUid,
        targetUsername: target.username || 'user',
        targetAvatar: target.avatarUrl,
        reporterUid,
        reporterUsername: reporter?.username || 'user',
        reason,
        details: details?.trim() || null,
    });
    return c.json({ success: true, message: 'User report submitted for moderation review' });
});
// ── 10. Submit Contact / Org Promotion Request ──────────────────────────────
const contactSchema = z.object({
    type: z.enum(['message', 'organization']).default('message'),
    subject: z.string().default('Contact Request'),
    message: z.string().min(1),
});
userRoutes.post('/contact-request', requireAuth, zValidator('json', contactSchema), async (c) => {
    const uid = c.get('uid');
    const user = c.get('user');
    const body = c.req.valid('json');
    const reqId = `cr_${randomBytes(12).toString('hex')}`;
    await db
        .insert(contactRequests)
        .values({
        id: reqId,
        userUid: uid,
        username: user.username || 'User',
        email: user.email,
        type: body.type,
        subject: body.subject,
        message: body.message,
    });
    const [created] = await db.select().from(contactRequests).where(eq(contactRequests.id, reqId)).limit(1);
    return c.json({ success: true, data: created }, 201);
});
// ── 11. Submit Error / Crash Report ─────────────────────────────────────────
const errorReportSchema = z.object({
    error: z.string().min(1),
    stackTrace: z.string().optional(),
    screen: z.string().default('unknown'),
    appVersion: z.string().optional(),
    platform: z.string().optional(),
});
userRoutes.post('/error-report', optionalAuth, zValidator('json', errorReportSchema), async (c) => {
    const uid = c.get('uid') || null;
    const body = c.req.valid('json');
    const reportId = `err_${randomBytes(12).toString('hex')}`;
    await db.insert(errorReports).values({
        id: reportId,
        error: body.error,
        stackTrace: body.stackTrace || null,
        screen: body.screen,
        appVersion: body.appVersion || null,
        platform: body.platform || null,
        userUid: uid,
    });
    return c.json({ success: true, recorded: true }, 201);
});
