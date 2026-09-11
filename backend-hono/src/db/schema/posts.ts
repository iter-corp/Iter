import { mysqlTable, text, timestamp, boolean, int, json, double, varchar, uniqueIndex } from 'drizzle-orm/mysql-core';
import { users } from './users.js';

export const posts = mysqlTable('posts', {
  id: varchar('id', { length: 128 }).primaryKey(),
  authorUid: varchar('author_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  authorUsername: varchar('author_username', { length: 64 }).notNull(),
  authorAvatar: text('author_avatar'),
  caption: text('caption').notNull(),
  imageUrls: json('image_urls').$type<string[]>().default([]).notNull(),
  videoUrls: json('video_urls').$type<string[]>().default([]).notNull(),
  likesCount: int('likes_count').default(0).notNull(),
  commentsCount: int('comments_count').default(0).notNull(),
  isPrivate: boolean('is_private').default(false).notNull(),
  postType: varchar('post_type', { length: 32 }).default('regular').notNull(), // 'regular' | 'qa'
  discussKind: varchar('discuss_kind', { length: 32 }).default('question').notNull(), // 'question' | 'discussion'
  sourcePostId: varchar('source_post_id', { length: 128 }),
  postPlaceName: varchar('post_place_name', { length: 255 }),
  postPlaceCity: varchar('post_place_city', { length: 128 }),
  postLat: double('post_lat'),
  postLng: double('post_lng'),
  postLocationExact: boolean('post_location_exact').default(false).notNull(),
  placeSearchKey: varchar('place_search_key', { length: 255 }),
  metadata: json('metadata').$type<Record<string, unknown>>().default({}).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});

export const postLikes = mysqlTable('post_likes', {
  id: varchar('id', { length: 255 }).primaryKey(), // `${postId}_${uid}`
  postId: varchar('post_id', { length: 128 }).notNull().references(() => posts.id, { onDelete: 'cascade' }),
  uid: varchar('uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('post_likes_pair_idx').on(table.postId, table.uid),
]);

export const postReposts = mysqlTable('post_reposts', {
  id: varchar('id', { length: 255 }).primaryKey(), // `${postId}_${uid}`
  postId: varchar('post_id', { length: 128 }).notNull().references(() => posts.id, { onDelete: 'cascade' }),
  uid: varchar('uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('post_reposts_pair_idx').on(table.postId, table.uid),
]);

export const postSaves = mysqlTable('post_saves', {
  id: varchar('id', { length: 255 }).primaryKey(), // `${postId}_${uid}`
  postId: varchar('post_id', { length: 128 }).notNull().references(() => posts.id, { onDelete: 'cascade' }),
  uid: varchar('uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('post_saves_pair_idx').on(table.postId, table.uid),
]);

export const postReports = mysqlTable('post_reports', {
  id: varchar('id', { length: 255 }).primaryKey(), // `${postId}_${reporterUid}`
  postId: varchar('post_id', { length: 128 }).notNull().references(() => posts.id, { onDelete: 'cascade' }),
  postAuthorUid: varchar('post_author_uid', { length: 128 }).notNull(),
  postAuthorUsername: varchar('post_author_username', { length: 64 }).notNull(),
  postAuthorAvatar: text('post_author_avatar'),
  postCaption: text('post_caption').notNull(),
  reporterUid: varchar('reporter_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  reporterUsername: varchar('reporter_username', { length: 64 }).notNull(),
  reason: varchar('reason', { length: 255 }).notNull(),
  details: text('details'),
  isQa: boolean('is_qa').default(false).notNull(),
  resolved: boolean('resolved').default(false).notNull(),
  resolvedAt: timestamp('resolved_at'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});
