import { mysqlTable, text, timestamp, boolean, int, varchar, uniqueIndex } from 'drizzle-orm/mysql-core';
import { users } from './users.js';
import { posts } from './posts.js';

export const comments = mysqlTable('comments', {
  id: varchar('id', { length: 128 }).primaryKey(),
  postId: varchar('post_id', { length: 128 }).notNull().references(() => posts.id, { onDelete: 'cascade' }),
  authorUid: varchar('author_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  authorUsername: varchar('author_username', { length: 64 }).notNull(),
  authorAvatar: text('author_avatar'),
  text: text('text').notNull(),
  parentCommentId: varchar('parent_comment_id', { length: 128 }),
  replyToUsername: varchar('reply_to_username', { length: 64 }),
  helpfulCount: int('helpful_count').default(0).notNull(),
  unhelpfulCount: int('unhelpful_count').default(0).notNull(),
  likesCount: int('likes_count').default(0).notNull(),
  profanityFiltered: boolean('profanity_filtered').default(false).notNull(),
  senderOnly: boolean('sender_only').default(false).notNull(),
  markedHelpful: boolean('marked_helpful').default(false).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});

export const commentLikes = mysqlTable('comment_likes', {
  id: varchar('id', { length: 255 }).primaryKey(), // `${commentId}_${uid}`
  commentId: varchar('comment_id', { length: 128 }).notNull().references(() => comments.id, { onDelete: 'cascade' }),
  uid: varchar('uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('comment_likes_pair_idx').on(table.commentId, table.uid),
]);

export const commentHelpfulVotes = mysqlTable('comment_helpful_votes', {
  id: varchar('id', { length: 255 }).primaryKey(), // `${commentId}_${uid}`
  commentId: varchar('comment_id', { length: 128 }).notNull().references(() => comments.id, { onDelete: 'cascade' }),
  uid: varchar('uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  isHelpful: boolean('is_helpful').notNull(), // true = helpful, false = unhelpful
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('comment_helpful_votes_pair_idx').on(table.commentId, table.uid),
]);

export const commentReports = mysqlTable('comment_reports', {
  id: varchar('id', { length: 255 }).primaryKey(),
  commentId: varchar('comment_id', { length: 128 }).notNull().references(() => comments.id, { onDelete: 'cascade' }),
  postId: varchar('post_id', { length: 128 }).notNull().references(() => posts.id, { onDelete: 'cascade' }),
  commentAuthorUid: varchar('comment_author_uid', { length: 128 }).notNull(),
  commentAuthorUsername: varchar('comment_author_username', { length: 64 }).notNull(),
  commentText: text('comment_text').notNull(),
  reporterUid: varchar('reporter_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  reporterUsername: varchar('reporter_username', { length: 64 }).notNull(),
  reason: varchar('reason', { length: 255 }).notNull(),
  resolved: boolean('resolved').default(false).notNull(),
  resolvedAt: timestamp('resolved_at'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});
