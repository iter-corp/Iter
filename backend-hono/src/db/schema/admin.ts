import { mysqlTable, text, timestamp, boolean, int, json, bigint, varchar } from 'drizzle-orm/mysql-core';
import { users } from './users.js';

export const apiKeys = mysqlTable('api_keys', {
  id: varchar('id', { length: 128 }).primaryKey(),
  provider: varchar('provider', { length: 64 }).notNull(), // 'gemini' | 'claude' | 'openai' | 'azure'
  key: text('key').notNull(),
  active: boolean('active').default(true).notNull(),
  priority: int('priority').default(999).notNull(), // lower = tried first
  statusMessage: text('status_message'),
  lastChecked: timestamp('last_checked'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});

export const apiLogs = mysqlTable('api_logs', {
  id: bigint('id', { mode: 'number', unsigned: true }).autoincrement().primaryKey(),
  provider: varchar('provider', { length: 64 }).notNull(),
  keyId: varchar('key_id', { length: 128 }),
  success: boolean('success').notNull(),
  wasFallback: boolean('was_fallback').default(false).notNull(),
  error: text('error'),
  nextProvider: varchar('next_provider', { length: 64 }),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});

export const contactRequests = mysqlTable('contact_requests', {
  id: varchar('id', { length: 128 }).primaryKey(),
  userUid: varchar('user_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  username: varchar('username', { length: 64 }).notNull(),
  email: varchar('email', { length: 191 }).notNull(),
  type: varchar('type', { length: 32 }).default('message').notNull(), // 'message' | 'organization'
  subject: varchar('subject', { length: 255 }).notNull(),
  message: text('message').notNull(),
  status: varchar('status', { length: 32 }).default('open').notNull(), // 'open' | 'answered' | 'promoted' | 'revoked'
  adminNotes: text('admin_notes'),
  repliedAt: timestamp('replied_at'),
  repliedBy: varchar('replied_by', { length: 128 }),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});

export const errorReports = mysqlTable('error_reports', {
  id: varchar('id', { length: 128 }).primaryKey(),
  error: text('error').notNull(),
  stackTrace: text('stack_trace'),
  screen: varchar('screen', { length: 128 }).default('unknown').notNull(),
  appVersion: varchar('app_version', { length: 64 }),
  platform: varchar('platform', { length: 32 }),
  userUid: varchar('user_uid', { length: 128 }),
  resolved: boolean('resolved').default(false).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});

export const stickerPacks = mysqlTable('sticker_packs', {
  id: varchar('id', { length: 128 }).primaryKey(),
  name: varchar('name', { length: 128 }).notNull(),
  ownerUid: varchar('owner_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
  stickerUrls: json('sticker_urls').$type<string[]>().default([]).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});
