import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';
import { db } from '../db/index.js';
import { chats, messages, users } from '../db/schema/index.js';
import { eq, and, sql, desc, inArray } from 'drizzle-orm';
import { AppError } from '../middleware/error-handler.js';
import { requireAuth } from '../middleware/auth.js';
import { findProfanityMatches } from '../services/profanity.service.js';
import { sendPushNotification } from '../services/fcm.service.js';
import { realtimeService } from '../services/websocket.service.js';
import { randomBytes } from 'crypto';
export const chatRoutes = new Hono();
function buildChatId(a, b) {
    const sorted = [a, b].sort();
    return `${sorted[0]}_${sorted[1]}`;
}
// ── 1. List Conversations for Current User ──────────────────────────────────
chatRoutes.get('/conversations', requireAuth, async (c) => {
    const uid = c.get('uid');
    const type = c.req.query('type') || 'all'; // 'all' | 'requests'
    // Fetch chats where user is in participants
    const allChats = await db
        .select()
        .from(chats)
        .where(sql `JSON_CONTAINS(${chats.participants}, JSON_QUOTE(${uid}))`)
        .orderBy(desc(chats.lastTime));
    const conversations = allChats.map((chat) => {
        const isGroup = chat.kind === 'group';
        let otherUid = '';
        let otherUsername = 'User';
        let otherAvatarUrl = '';
        if (!isGroup) {
            otherUid = chat.participants.find((p) => p !== uid) || '';
            const otherInfo = chat.userData[otherUid];
            if (otherInfo) {
                otherUsername = otherInfo.username || 'User';
                otherAvatarUrl = otherInfo.avatarUrl || '';
            }
        }
        const isRequest = !isGroup && !chat.acceptedBy.includes(uid);
        const unreadCount = chat.unreadCounts[uid] || 0;
        const isMuted = chat.mutedFor.includes(uid);
        return {
            chatId: chat.id,
            isGroup,
            groupName: chat.groupName,
            groupAvatarUrl: chat.groupAvatarUrl,
            adminUid: chat.adminUid,
            participants: chat.participants,
            otherUid,
            otherUsername,
            otherAvatarUrl,
            lastMessage: chat.lastMessage,
            lastTime: chat.lastTime,
            unreadCount,
            isRequest,
            isMuted,
            isOnline: otherUid ? realtimeService.isUserOnline(otherUid) : false,
            lastSeen: otherUid ? realtimeService.getUserLastSeen(otherUid) : null,
        };
    });
    const filtered = type === 'requests'
        ? conversations.filter((c) => c.isRequest)
        : conversations.filter((c) => !c.isRequest);
    return c.json({ success: true, data: filtered });
});
// ── 2. Get or Create 1:1 Direct Chat ────────────────────────────────────────
chatRoutes.get('/direct/:otherUid', requireAuth, async (c) => {
    const uid = c.get('uid');
    const otherUid = c.req.param('otherUid');
    if (uid === otherUid) {
        throw new AppError('Cannot start chat with yourself', 400, 'INVALID_CHAT');
    }
    const chatId = buildChatId(uid, otherUid);
    let [chat] = await db.select().from(chats).where(eq(chats.id, chatId)).limit(1);
    if (!chat) {
        const [me, other] = await Promise.all([
            db.select({ id: users.id, username: users.username, avatarUrl: users.avatarUrl }).from(users).where(eq(users.id, uid)).limit(1),
            db.select({ id: users.id, username: users.username, avatarUrl: users.avatarUrl }).from(users).where(eq(users.id, otherUid)).limit(1),
        ]);
        if (!other[0])
            throw new AppError('Other user not found', 404, 'NOT_FOUND');
        const userData = {
            [uid]: { username: me[0]?.username || 'User', avatarUrl: me[0]?.avatarUrl || undefined },
            [otherUid]: { username: other[0]?.username || 'User', avatarUrl: other[0]?.avatarUrl || undefined },
        };
        await db
            .insert(chats)
            .values({
            id: chatId,
            kind: 'direct',
            participants: [uid, otherUid],
            acceptedBy: [uid], // Creator auto-accepts
            userData,
        });
        const [created] = await db.select().from(chats).where(eq(chats.id, chatId)).limit(1);
        chat = created;
    }
    return c.json({ success: true, data: chat });
});
// ── 3. Create Group Chat ────────────────────────────────────────────────────
const createGroupSchema = z.object({
    groupName: z.string().min(1).max(50),
    groupAvatarUrl: z.string().optional(),
    participantUids: z.array(z.string()).min(1),
});
chatRoutes.post('/group', requireAuth, zValidator('json', createGroupSchema), async (c) => {
    const uid = c.get('uid');
    const { groupName, groupAvatarUrl, participantUids } = c.req.valid('json');
    const allMembers = Array.from(new Set([uid, ...participantUids]));
    const memberDocs = await db.select().from(users).where(inArray(users.id, allMembers));
    const userData = {};
    for (const m of memberDocs) {
        userData[m.id] = { username: m.username || 'User', avatarUrl: m.avatarUrl || undefined };
    }
    const groupId = `grp_${randomBytes(12).toString('hex')}`;
    await db
        .insert(chats)
        .values({
        id: groupId,
        kind: 'group',
        groupName,
        groupAvatarUrl: groupAvatarUrl || '',
        adminUid: uid,
        participants: allMembers,
        acceptedBy: allMembers,
        userData,
    });
    const [groupChat] = await db.select().from(chats).where(eq(chats.id, groupId)).limit(1);
    return c.json({ success: true, data: groupChat }, 201);
});
// ── 4. List Messages in Chat ────────────────────────────────────────────────
chatRoutes.get('/:chatId/messages', requireAuth, async (c) => {
    const chatId = c.req.param('chatId');
    const uid = c.get('uid');
    const limit = Math.min(Number(c.req.query('limit')) || 50, 100);
    const [chat] = await db.select().from(chats).where(eq(chats.id, chatId)).limit(1);
    if (!chat || !chat.participants.includes(uid)) {
        throw new AppError('Chat not found or access denied', 404, 'NOT_FOUND');
    }
    const chatMessages = await db
        .select()
        .from(messages)
        .where(and(eq(messages.chatId, chatId), eq(messages.deletedForEveryone, false), sql `NOT JSON_CONTAINS(COALESCE(${messages.deletedForUids}, '[]'), JSON_QUOTE(${uid}))`))
        .orderBy(desc(messages.createdAt))
        .limit(limit);
    return c.json({ success: true, data: chatMessages.reverse() });
});
// ── 5. Send Message ─────────────────────────────────────────────────────────
const sendMessageSchema = z.object({
    text: z.string().default(''),
    imageUrl: z.string().optional(),
    videoUrl: z.string().optional(),
    fileUrl: z.string().optional(),
    fileName: z.string().optional(),
    fileMimeType: z.string().optional(),
    fileSizeBytes: z.number().optional(),
    voiceUrl: z.string().optional(),
    voiceDurationMs: z.number().optional(),
    voiceTranscript: z.string().optional(),
    stickerUrl: z.string().optional(),
    stickerPackId: z.string().optional(),
    sharedPostId: z.string().optional(),
    sharedEventId: z.string().optional(),
    storyId: z.string().optional(),
    storyImageUrl: z.string().optional(),
    replyToId: z.string().optional(),
    replyToText: z.string().optional(),
    replyToSenderUid: z.string().optional(),
    locationLat: z.number().optional(),
    locationLng: z.number().optional(),
    locationLabel: z.string().optional(),
});
chatRoutes.post('/:chatId/messages', requireAuth, zValidator('json', sendMessageSchema), async (c) => {
    const chatId = c.req.param('chatId');
    const uid = c.get('uid');
    const body = c.req.valid('json');
    const [chat] = await db.select().from(chats).where(eq(chats.id, chatId)).limit(1);
    if (!chat || !chat.participants.includes(uid)) {
        throw new AppError('Chat not found or access denied', 404, 'NOT_FOUND');
    }
    // Check profanity
    const matches = await findProfanityMatches(body.text);
    const isProfane = matches.length > 0;
    const messageId = `msg_${randomBytes(12).toString('hex')}`;
    const now = new Date();
    const [newMsg] = await db
        .insert(messages)
        .values({
        id: messageId,
        chatId,
        senderUid: uid,
        text: body.text,
        senderOnlyText: isProfane ? body.text : null,
        imageUrl: body.imageUrl || null,
        videoUrl: body.videoUrl || null,
        fileUrl: body.fileUrl || null,
        fileName: body.fileName || null,
        fileMimeType: body.fileMimeType || null,
        fileSizeBytes: body.fileSizeBytes || null,
        voiceUrl: body.voiceUrl || null,
        voiceDurationMs: body.voiceDurationMs || null,
        voiceTranscript: body.voiceTranscript || null,
        stickerUrl: body.stickerUrl || null,
        stickerPackId: body.stickerPackId || null,
        sharedPostId: body.sharedPostId || null,
        sharedEventId: body.sharedEventId || null,
        storyId: body.storyId || null,
        storyImageUrl: body.storyImageUrl || null,
        replyToId: body.replyToId || null,
        replyToText: body.replyToText || null,
        replyToSenderUid: body.replyToSenderUid || null,
        locationLat: body.locationLat || null,
        locationLng: body.locationLng || null,
        locationLabel: body.locationLabel || null,
        seenBy: [uid],
        visibleToUids: isProfane ? [uid] : chat.participants,
        profanityFiltered: isProfane,
        createdAt: now,
    });
    const [newMessage] = await db.select().from(messages).where(eq(messages.id, messageId)).limit(1);
    // Preview snippet for lastMessage
    let previewText = body.text.trim();
    if (!previewText) {
        if (body.imageUrl)
            previewText = 'Sent a photo';
        else if (body.videoUrl)
            previewText = 'Sent a video';
        else if (body.voiceUrl)
            previewText = 'Voice message';
        else if (body.stickerUrl)
            previewText = 'Sent a sticker';
        else if (body.fileUrl)
            previewText = 'Sent a file';
        else if (body.locationLat)
            previewText = '📍 Shared a location';
        else
            previewText = 'Message';
    }
    // Update chat summary & increment unread count for recipients
    const nextUnread = { ...(chat.unreadCounts || {}) };
    nextUnread[uid] = 0;
    if (!isProfane) {
        for (const p of chat.participants) {
            if (p !== uid) {
                nextUnread[p] = (nextUnread[p] || 0) + 1;
            }
        }
    }
    await db
        .update(chats)
        .set({
        lastMessage: previewText,
        lastMessageSenderUid: uid,
        lastTime: now,
        unreadCounts: nextUnread,
        acceptedBy: Array.from(new Set([...chat.acceptedBy, uid])),
    })
        .where(eq(chats.id, chatId));
    // Push realtime WebSocket message to all active participants
    if (!isProfane) {
        for (const recipientUid of chat.participants) {
            if (recipientUid !== uid) {
                realtimeService.sendToUser(recipientUid, {
                    type: 'new_message',
                    chatId,
                    message: newMsg,
                });
                // Check if chat is muted
                if (!chat.mutedFor.includes(recipientUid)) {
                    const senderName = chat.userData[uid]?.username || 'Someone';
                    sendPushNotification({
                        targetUid: recipientUid,
                        title: chat.kind === 'group' ? chat.groupName : senderName,
                        body: chat.kind === 'group' ? `${senderName}: ${previewText}` : previewText,
                        type: 'message',
                        actorUid: uid,
                        targetId: chatId,
                    });
                }
            }
        }
    }
    return c.json({ success: true, data: newMsg }, 201);
});
// ── 6. Mark Seen in Chat ────────────────────────────────────────────────────
chatRoutes.post('/:chatId/seen', requireAuth, async (c) => {
    const chatId = c.req.param('chatId');
    const uid = c.get('uid');
    const [chat] = await db.select().from(chats).where(eq(chats.id, chatId)).limit(1);
    if (chat) {
        const unread = { ...(chat.unreadCounts || {}) };
        unread[uid] = 0;
        await db.update(chats).set({ unreadCounts: unread }).where(eq(chats.id, chatId));
    }
    // Update unseen messages
    await db.execute(sql `
    UPDATE messages
    SET seen_by = JSON_ARRAY_APPEND(COALESCE(seen_by, JSON_ARRAY()), '$', ${uid})
    WHERE chat_id = ${chatId} AND NOT JSON_CONTAINS(COALESCE(seen_by, JSON_ARRAY()), JSON_QUOTE(${uid}))
  `);
    return c.json({ success: true });
});
// ── 7. Toggle Mute Chat ─────────────────────────────────────────────────────
chatRoutes.post('/:chatId/mute', requireAuth, async (c) => {
    const chatId = c.req.param('chatId');
    const uid = c.get('uid');
    const [chat] = await db.select().from(chats).where(eq(chats.id, chatId)).limit(1);
    if (!chat)
        throw new AppError('Chat not found', 404, 'NOT_FOUND');
    const isMuted = chat.mutedFor.includes(uid);
    const nextMuted = isMuted
        ? chat.mutedFor.filter((m) => m !== uid)
        : [...chat.mutedFor, uid];
    await db.update(chats).set({ mutedFor: nextMuted }).where(eq(chats.id, chatId));
    return c.json({ success: true, muted: !isMuted });
});
