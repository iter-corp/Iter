import { pgTable, text, timestamp, uniqueIndex } from 'drizzle-orm/pg-core';
import { users } from './users.js';

export const follows = pgTable('follows', {
  id: text('id').primaryKey(), // `${followerUid}_${targetUid}`
  followerUid: text('follower_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  targetUid: text('target_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  status: text('status').default('active').notNull(), // 'active' | 'pending'
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('follows_follower_target_idx').on(table.followerUid, table.targetUid),
]);

export const blocks = pgTable('blocks', {
  id: text('id').primaryKey(), // `${blockerUid}_${blockedUid}`
  blockerUid: text('blocker_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  blockedUid: text('blocked_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('blocks_blocker_blocked_idx').on(table.blockerUid, table.blockedUid),
]);
