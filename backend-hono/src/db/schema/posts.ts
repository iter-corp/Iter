import { pgTable, text, timestamp, boolean, integer, jsonb, doublePrecision, uniqueIndex } from 'drizzle-orm/pg-core';
import { users } from './users.js';

export const posts = pgTable('posts', {
  id: text('id').primaryKey(), // doc id
  authorUid: text('author_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  authorUsername: text('author_username').notNull(),
  authorAvatar: text('author_avatar'),
  caption: text('caption').notNull(),
  imageUrls: jsonb('image_urls').$type<string[]>().default([]).notNull(),
  videoUrls: jsonb('video_urls').$type<string[]>().default([]).notNull(),
  likesCount: integer('likes_count').default(0).notNull(),
  commentsCount: integer('comments_count').default(0).notNull(),
  isPrivate: boolean('is_private').default(false).notNull(),
  postType: text('post_type').default('regular').notNull(), // 'regular' | 'qa'
  discussKind: text('discuss_kind').default('question').notNull(), // 'question' | 'discussion'
  sourcePostId: text('source_post_id'),
  postPlaceName: text('post_place_name'),
  postPlaceCity: text('post_place_city'),
  postLat: doublePrecision('post_lat'),
  postLng: doublePrecision('post_lng'),
  postLocationExact: boolean('post_location_exact').default(false).notNull(),
  placeSearchKey: text('place_search_key'),
  metadata: jsonb('metadata').$type<Record<string, unknown>>().default({}).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});

export const postLikes = pgTable('post_likes', {
  id: text('id').primaryKey(), // `${postId}_${uid}`
  postId: text('post_id').notNull().references(() => posts.id, { onDelete: 'cascade' }),
  uid: text('uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('post_likes_pair_idx').on(table.postId, table.uid),
]);

export const postReposts = pgTable('post_reposts', {
  id: text('id').primaryKey(), // `${postId}_${uid}`
  postId: text('post_id').notNull().references(() => posts.id, { onDelete: 'cascade' }),
  uid: text('uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('post_reposts_pair_idx').on(table.postId, table.uid),
]);

export const postSaves = pgTable('post_saves', {
  id: text('id').primaryKey(), // `${postId}_${uid}`
  postId: text('post_id').notNull().references(() => posts.id, { onDelete: 'cascade' }),
  uid: text('uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('post_saves_pair_idx').on(table.postId, table.uid),
]);

export const postReports = pgTable('post_reports', {
  id: text('id').primaryKey(), // `${postId}_${reporterUid}`
  postId: text('post_id').notNull().references(() => posts.id, { onDelete: 'cascade' }),
  postAuthorUid: text('post_author_uid').notNull(),
  postAuthorUsername: text('post_author_username').notNull(),
  postAuthorAvatar: text('post_author_avatar'),
  postCaption: text('post_caption').notNull(),
  reporterUid: text('reporter_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  reporterUsername: text('reporter_username').notNull(),
  reason: text('reason').notNull(),
  details: text('details'),
  isQa: boolean('is_qa').default(false).notNull(),
  resolved: boolean('resolved').default(false).notNull(),
  resolvedAt: timestamp('resolved_at'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});
