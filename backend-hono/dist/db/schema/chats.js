import { mysqlTable, text, timestamp, boolean, int, json, double, varchar, uniqueIndex } from 'drizzle-orm/mysql-core';
import { users } from './users.js';
export const chats = mysqlTable('chats', {
    id: varchar('id', { length: 128 }).primaryKey(), // direct: 'uidA_uidB', group: uuid
    kind: varchar('kind', { length: 32 }).default('direct').notNull(), // 'direct' | 'group'
    groupName: varchar('group_name', { length: 128 }).default('').notNull(),
    groupAvatarUrl: text('group_avatar_url'),
    adminUid: varchar('admin_uid', { length: 128 }).default('').notNull(),
    lastMessage: text('last_message').default('').notNull(),
    lastMessageSenderUid: varchar('last_message_sender_uid', { length: 128 }).default('').notNull(),
    lastTime: timestamp('last_time').defaultNow().notNull(),
    participants: json('participants').$type().default([]).notNull(),
    acceptedBy: json('accepted_by').$type().default([]).notNull(),
    mutedFor: json('muted_for').$type().default([]).notNull(),
    unreadCounts: json('unread_counts').$type().default({}).notNull(),
    userData: json('user_data').$type().default({}).notNull(),
    metadata: json('metadata').$type().default({}).notNull(),
    createdAt: timestamp('created_at').defaultNow().notNull(),
    updatedAt: timestamp('updated_at').defaultNow().notNull(),
});
export const messages = mysqlTable('messages', {
    id: varchar('id', { length: 128 }).primaryKey(),
    chatId: varchar('chat_id', { length: 128 }).notNull().references(() => chats.id, { onDelete: 'cascade' }),
    senderUid: varchar('sender_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    text: text('text').default('').notNull(),
    senderOnlyText: text('sender_only_text'),
    imageUrl: text('image_url'),
    videoUrl: text('video_url'),
    fileUrl: text('file_url'),
    fileName: varchar('file_name', { length: 255 }),
    fileMimeType: varchar('file_mime_type', { length: 128 }),
    fileSizeBytes: int('file_size_bytes'),
    voiceUrl: text('voice_url'),
    voiceDurationMs: int('voice_duration_ms'),
    voiceTranscript: text('voice_transcript'),
    stickerUrl: text('sticker_url'),
    stickerPackId: varchar('sticker_pack_id', { length: 128 }),
    sharedPostId: varchar('shared_post_id', { length: 128 }),
    sharedEventId: varchar('shared_event_id', { length: 128 }),
    storyId: varchar('story_id', { length: 128 }),
    storyImageUrl: text('story_image_url'),
    replyToId: varchar('reply_to_id', { length: 128 }),
    replyToText: text('reply_to_text'),
    replyToSenderUid: varchar('reply_to_sender_uid', { length: 128 }),
    locationLat: double('location_lat'),
    locationLng: double('location_lng'),
    locationLabel: varchar('location_label', { length: 255 }),
    seenBy: json('seen_by').$type().default([]).notNull(),
    visibleToUids: json('visible_to_uids').$type().default([]).notNull(),
    deletedForUids: json('deleted_for_uids').$type().default([]).notNull(),
    deletedForEveryone: boolean('deleted_for_everyone').default(false).notNull(),
    profanityFiltered: boolean('profanity_filtered').default(false).notNull(),
    createdAt: timestamp('created_at').defaultNow().notNull(),
});
export const messageReactions = mysqlTable('message_reactions', {
    id: varchar('id', { length: 255 }).primaryKey(), // `${messageId}_${uid}`
    messageId: varchar('message_id', { length: 128 }).notNull().references(() => messages.id, { onDelete: 'cascade' }),
    uid: varchar('uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    reaction: varchar('reaction', { length: 64 }).notNull(),
    createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
    uniqueIndex('message_reactions_pair_idx').on(table.messageId, table.uid),
]);
