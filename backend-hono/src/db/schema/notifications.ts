import { pgTable, text, timestamp, boolean, serial, uniqueIndex } from 'drizzle-orm/pg-core';
import { users } from './users.js';

export const notifications = pgTable('notifications', {
  id: text('id').primaryKey(),
  targetUid: text('target_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  type: text('type').notNull(), // 'follow', 'like', 'comment', 'message', 'new_event', etc.
  actorUid: text('actor_uid').default('').notNull(),
  targetId: text('target_id'),
  commentId: text('comment_id'),
  title: text('title'),
  subtitle: text('subtitle'),
  status: text('status'),
  read: boolean('read').default(false).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});

export const fcmTokens = pgTable('fcm_tokens', {
  id: serial('id').primaryKey(),
  uid: text('uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  token: text('token').notNull().unique(),
  deviceType: text('device_type').default('unknown').notNull(), // 'ios' | 'android' | 'web'
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('fcm_tokens_uid_token_idx').on(table.uid, table.token),
]);
