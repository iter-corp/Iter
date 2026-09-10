import { pgTable, text, timestamp, boolean, integer, jsonb, uniqueIndex } from 'drizzle-orm/pg-core';
import { users } from './users.js';

export const polls = pgTable('polls', {
  id: text('id').primaryKey(),
  question: text('question').notNull(),
  options: jsonb('options').$type<string[]>().default([]).notNull(),
  createdByUid: text('created_by_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  visibility: text('visibility').default('public').notNull(), // 'public' | 'secret'
  closed: boolean('closed').default(false).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});

export const pollVotes = pgTable('poll_votes', {
  id: text('id').primaryKey(), // `${pollId}_${uid}`
  pollId: text('poll_id').notNull().references(() => polls.id, { onDelete: 'cascade' }),
  uid: text('uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  optionIndex: integer('option_index').notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('poll_votes_pair_idx').on(table.pollId, table.uid),
]);
