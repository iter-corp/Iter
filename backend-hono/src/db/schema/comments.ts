import { pgTable, text, timestamp, boolean, integer, uniqueIndex } from 'drizzle-orm/pg-core';
import { users } from './users.js';
import { posts } from './posts.js';

export const comments = pgTable('comments', {
  id: text('id').primaryKey(),
  postId: text('post_id').notNull().references(() => posts.id, { onDelete: 'cascade' }),
  authorUid: text('author_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  authorUsername: text('author_username').notNull(),
  authorAvatar: text('author_avatar'),
  text: text('text').notNull(),
  parentCommentId: text('parent_comment_id'),
  replyToUsername: text('reply_to_username'),
  helpfulCount: integer('helpful_count').default(0).notNull(),
  unhelpfulCount: integer('unhelpful_count').default(0).notNull(),
  likesCount: integer('likes_count').default(0).notNull(),
  profanityFiltered: boolean('profanity_filtered').default(false).notNull(),
  senderOnly: boolean('sender_only').default(false).notNull(),
  markedHelpful: boolean('marked_helpful').default(false).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});

export const commentLikes = pgTable('comment_likes', {
  id: text('id').primaryKey(), // `${commentId}_${uid}`
  commentId: text('comment_id').notNull().references(() => comments.id, { onDelete: 'cascade' }),
  uid: text('uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('comment_likes_pair_idx').on(table.commentId, table.uid),
]);

export const commentHelpfulVotes = pgTable('comment_helpful_votes', {
  id: text('id').primaryKey(), // `${commentId}_${uid}`
  commentId: text('comment_id').notNull().references(() => comments.id, { onDelete: 'cascade' }),
  uid: text('uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  isHelpful: boolean('is_helpful').notNull(), // true = helpful, false = unhelpful
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('comment_helpful_votes_pair_idx').on(table.commentId, table.uid),
]);

export const commentReports = pgTable('comment_reports', {
  id: text('id').primaryKey(),
  commentId: text('comment_id').notNull().references(() => comments.id, { onDelete: 'cascade' }),
  postId: text('post_id').notNull().references(() => posts.id, { onDelete: 'cascade' }),
  commentAuthorUid: text('comment_author_uid').notNull(),
  commentAuthorUsername: text('comment_author_username').notNull(),
  commentText: text('comment_text').notNull(),
  reporterUid: text('reporter_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  reporterUsername: text('reporter_username').notNull(),
  reason: text('reason').notNull(),
  resolved: boolean('resolved').default(false).notNull(),
  resolvedAt: timestamp('resolved_at'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});
