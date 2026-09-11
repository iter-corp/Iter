import { mysqlTable, text, timestamp, int, json, varchar, uniqueIndex } from 'drizzle-orm/mysql-core';
import { users } from './users.js';

export const stories = mysqlTable('stories', {
  id: varchar('id', { length: 128 }).primaryKey(),
  authorUid: varchar('author_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  authorUsername: varchar('author_username', { length: 64 }).notNull(),
  authorAvatar: text('author_avatar'),
  imageUrl: text('image_url').notNull(),
  videoUrl: text('video_url'),
  videoTrimStartMs: int('video_trim_start_ms'),
  videoTrimEndMs: int('video_trim_end_ms'),
  textContent: text('text_content'),
  backgroundColor: int('background_color'),
  textColor: int('text_color'),
  textBorderStyle: varchar('text_border_style', { length: 64 }),
  sharedPostId: varchar('shared_post_id', { length: 128 }),
  sharedEventId: varchar('shared_event_id', { length: 128 }),
  sharedEventTitle: varchar('shared_event_title', { length: 255 }),
  overlays: json('overlays').$type<Array<Record<string, unknown>>>().default([]).notNull(),
  likesCount: int('likes_count').default(0).notNull(),
  commentsCount: int('comments_count').default(0).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  expiresAt: timestamp('expires_at').notNull(),
});

export const storyViewers = mysqlTable('story_viewers', {
  id: varchar('id', { length: 255 }).primaryKey(), // `${storyId}_${uid}`
  storyId: varchar('story_id', { length: 128 }).notNull().references(() => stories.id, { onDelete: 'cascade' }),
  uid: varchar('uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  username: varchar('username', { length: 64 }).notNull(),
  avatarUrl: text('avatar_url'),
  viewedAt: timestamp('viewed_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('story_viewers_pair_idx').on(table.storyId, table.uid),
]);

export const storyLikes = mysqlTable('story_likes', {
  id: varchar('id', { length: 255 }).primaryKey(), // `${storyId}_${uid}`
  storyId: varchar('story_id', { length: 128 }).notNull().references(() => stories.id, { onDelete: 'cascade' }),
  uid: varchar('uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('story_likes_pair_idx').on(table.storyId, table.uid),
]);
