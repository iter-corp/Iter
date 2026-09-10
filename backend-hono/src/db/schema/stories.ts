import { pgTable, text, timestamp, integer, jsonb, uniqueIndex } from 'drizzle-orm/pg-core';
import { users } from './users.js';

export const stories = pgTable('stories', {
  id: text('id').primaryKey(),
  authorUid: text('author_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  authorUsername: text('author_username').notNull(),
  authorAvatar: text('author_avatar'),
  imageUrl: text('image_url').default('').notNull(),
  videoUrl: text('video_url'),
  videoTrimStartMs: integer('video_trim_start_ms'),
  videoTrimEndMs: integer('video_trim_end_ms'),
  textContent: text('text_content'),
  backgroundColor: integer('background_color'),
  textColor: integer('text_color'),
  textBorderStyle: text('text_border_style'),
  sharedPostId: text('shared_post_id'),
  sharedEventId: text('shared_event_id'),
  sharedEventTitle: text('shared_event_title'),
  overlays: jsonb('overlays').$type<Array<Record<string, unknown>>>().default([]).notNull(),
  likesCount: integer('likes_count').default(0).notNull(),
  commentsCount: integer('comments_count').default(0).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  expiresAt: timestamp('expires_at').notNull(),
});

export const storyViewers = pgTable('story_viewers', {
  id: text('id').primaryKey(), // `${storyId}_${uid}`
  storyId: text('story_id').notNull().references(() => stories.id, { onDelete: 'cascade' }),
  uid: text('uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  username: text('username').notNull(),
  avatarUrl: text('avatar_url'),
  viewedAt: timestamp('viewed_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('story_viewers_pair_idx').on(table.storyId, table.uid),
]);

export const storyLikes = pgTable('story_likes', {
  id: text('id').primaryKey(), // `${storyId}_${uid}`
  storyId: text('story_id').notNull().references(() => stories.id, { onDelete: 'cascade' }),
  uid: text('uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('story_likes_pair_idx').on(table.storyId, table.uid),
]);
