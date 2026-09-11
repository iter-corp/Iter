import { mysqlTable, text, timestamp, boolean, int, json, varchar, uniqueIndex } from 'drizzle-orm/mysql-core';
import { users } from './users.js';

export const polls = mysqlTable('polls', {
  id: varchar('id', { length: 128 }).primaryKey(),
  question: text('question').notNull(),
  options: json('options').$type<string[]>().default([]).notNull(),
  createdByUid: varchar('created_by_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  visibility: varchar('visibility', { length: 32 }).default('public').notNull(), // 'public' | 'secret'
  closed: boolean('closed').default(false).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});

export const pollVotes = mysqlTable('poll_votes', {
  id: varchar('id', { length: 255 }).primaryKey(), // `${pollId}_${uid}`
  pollId: varchar('poll_id', { length: 128 }).notNull().references(() => polls.id, { onDelete: 'cascade' }),
  uid: varchar('uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  optionIndex: int('option_index').notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('poll_votes_pair_idx').on(table.pollId, table.uid),
]);
