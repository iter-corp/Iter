import { pgTable, text, timestamp, boolean, integer, jsonb, doublePrecision, uniqueIndex } from 'drizzle-orm/pg-core';
import { users } from './users.js';

export const chats = pgTable('chats', {
  id: text('id').primaryKey(), // direct: 'uidA_uidB', group: uuid
  kind: text('kind').default('direct').notNull(), // 'direct' | 'group'
  groupName: text('group_name').default('').notNull(),
  groupAvatarUrl: text('group_avatar_url').default('').notNull(),
  adminUid: text('admin_uid').default('').notNull(),
  lastMessage: text('last_message').default('').notNull(),
  lastMessageSenderUid: text('last_message_sender_uid').default('').notNull(),
  lastTime: timestamp('last_time').defaultNow().notNull(),
  participants: jsonb('participants').$type<string[]>().default([]).notNull(),
  acceptedBy: jsonb('accepted_by').$type<string[]>().default([]).notNull(),
  mutedFor: jsonb('muted_for').$type<string[]>().default([]).notNull(),
  unreadCounts: jsonb('unread_counts').$type<Record<string, number>>().default({}).notNull(),
  userData: jsonb('user_data').$type<Record<string, { username: string; avatarUrl?: string }>>().default({}).notNull(),
  metadata: jsonb('metadata').$type<Record<string, unknown>>().default({}).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});

export const messages = pgTable('messages', {
  id: text('id').primaryKey(),
  chatId: text('chat_id').notNull().references(() => chats.id, { onDelete: 'cascade' }),
  senderUid: text('sender_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  text: text('text').default('').notNull(),
  senderOnlyText: text('sender_only_text'),
  imageUrl: text('image_url'),
  videoUrl: text('video_url'),
  fileUrl: text('file_url'),
  fileName: text('file_name'),
  fileMimeType: text('file_mime_type'),
  fileSizeBytes: integer('file_size_bytes'),
  voiceUrl: text('voice_url'),
  voiceDurationMs: integer('voice_duration_ms'),
  voiceTranscript: text('voice_transcript'),
  stickerUrl: text('sticker_url'),
  stickerPackId: text('sticker_pack_id'),
  sharedPostId: text('shared_post_id'),
  sharedEventId: text('shared_event_id'),
  storyId: text('story_id'),
  storyImageUrl: text('story_image_url'),
  replyToId: text('reply_to_id'),
  replyToText: text('reply_to_text'),
  replyToSenderUid: text('reply_to_sender_uid'),
  locationLat: doublePrecision('location_lat'),
  locationLng: doublePrecision('location_lng'),
  locationLabel: text('location_label'),
  seenBy: jsonb('seen_by').$type<string[]>().default([]).notNull(),
  visibleToUids: jsonb('visible_to_uids').$type<string[]>().default([]).notNull(),
  deletedForUids: jsonb('deleted_for_uids').$type<string[]>().default([]).notNull(),
  deletedForEveryone: boolean('deleted_for_everyone').default(false).notNull(),
  profanityFiltered: boolean('profanity_filtered').default(false).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});

export const messageReactions = pgTable('message_reactions', {
  id: text('id').primaryKey(), // `${messageId}_${uid}`
  messageId: text('message_id').notNull().references(() => messages.id, { onDelete: 'cascade' }),
  uid: text('uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  reaction: text('reaction').notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('message_reactions_pair_idx').on(table.messageId, table.uid),
]);
