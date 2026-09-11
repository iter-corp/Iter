import { mysqlTable, text, timestamp, boolean, serial, varchar, uniqueIndex } from 'drizzle-orm/mysql-core';
import { users } from './users.js';
export const notifications = mysqlTable('notifications', {
    id: varchar('id', { length: 128 }).primaryKey(),
    targetUid: varchar('target_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    type: varchar('type', { length: 64 }).notNull(), // 'follow', 'like', 'comment', 'message', 'new_event', etc.
    actorUid: varchar('actor_uid', { length: 128 }).default('').notNull(),
    targetId: varchar('target_id', { length: 128 }),
    commentId: varchar('comment_id', { length: 128 }),
    title: varchar('title', { length: 255 }),
    subtitle: text('subtitle'),
    status: varchar('status', { length: 64 }),
    read: boolean('read').default(false).notNull(),
    createdAt: timestamp('created_at').defaultNow().notNull(),
});
export const fcmTokens = mysqlTable('fcm_tokens', {
    id: serial('id').primaryKey(),
    uid: varchar('uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    token: varchar('token', { length: 512 }).notNull().unique(),
    deviceType: varchar('device_type', { length: 32 }).default('unknown').notNull(), // 'ios' | 'android' | 'web'
    createdAt: timestamp('created_at').defaultNow().notNull(),
    updatedAt: timestamp('updated_at').defaultNow().notNull(),
}, (table) => [
    uniqueIndex('fcm_tokens_uid_token_idx').on(table.uid, table.token),
]);
