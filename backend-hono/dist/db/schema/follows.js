import { mysqlTable, timestamp, varchar, uniqueIndex } from 'drizzle-orm/mysql-core';
import { users } from './users.js';
export const follows = mysqlTable('follows', {
    id: varchar('id', { length: 255 }).primaryKey(), // `${followerUid}_${targetUid}`
    followerUid: varchar('follower_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    targetUid: varchar('target_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    status: varchar('status', { length: 32 }).default('active').notNull(), // 'active' | 'pending'
    createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
    uniqueIndex('follows_follower_target_idx').on(table.followerUid, table.targetUid),
]);
export const blocks = mysqlTable('blocks', {
    id: varchar('id', { length: 255 }).primaryKey(), // `${blockerUid}_${blockedUid}`
    blockerUid: varchar('blocker_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    blockedUid: varchar('blocked_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
    uniqueIndex('blocks_blocker_blocked_idx').on(table.blockerUid, table.blockedUid),
]);
