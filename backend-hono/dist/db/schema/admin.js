import { pgTable, text, timestamp, boolean, integer, jsonb, serial } from 'drizzle-orm/pg-core';
import { users } from './users.js';
export const apiKeys = pgTable('api_keys', {
    id: text('id').primaryKey(),
    provider: text('provider').notNull(), // 'gemini' | 'claude' | 'openai' | 'azure'
    key: text('key').notNull(),
    active: boolean('active').default(true).notNull(),
    priority: integer('priority').default(999).notNull(), // lower = tried first
    statusMessage: text('status_message'),
    lastChecked: timestamp('last_checked'),
    createdAt: timestamp('created_at').defaultNow().notNull(),
    updatedAt: timestamp('updated_at').defaultNow().notNull(),
});
export const apiLogs = pgTable('api_logs', {
    id: serial('id').primaryKey(),
    provider: text('provider').notNull(),
    keyId: text('key_id'),
    success: boolean('success').notNull(),
    wasFallback: boolean('was_fallback').default(false).notNull(),
    error: text('error'),
    nextProvider: text('next_provider'),
    createdAt: timestamp('created_at').defaultNow().notNull(),
});
export const contactRequests = pgTable('contact_requests', {
    id: text('id').primaryKey(),
    userUid: text('user_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
    username: text('username').notNull(),
    email: text('email').notNull(),
    type: text('type').default('message').notNull(), // 'message' | 'organization'
    subject: text('subject').notNull(),
    message: text('message').notNull(),
    status: text('status').default('open').notNull(), // 'open' | 'answered' | 'promoted' | 'revoked'
    adminNotes: text('admin_notes'),
    repliedAt: timestamp('replied_at'),
    repliedBy: text('replied_by'),
    createdAt: timestamp('created_at').defaultNow().notNull(),
    updatedAt: timestamp('updated_at').defaultNow().notNull(),
});
export const errorReports = pgTable('error_reports', {
    id: text('id').primaryKey(),
    error: text('error').notNull(),
    stackTrace: text('stack_trace'),
    screen: text('screen').default('unknown').notNull(),
    appVersion: text('app_version'),
    platform: text('platform'),
    userUid: text('user_uid'),
    resolved: boolean('resolved').default(false).notNull(),
    createdAt: timestamp('created_at').defaultNow().notNull(),
});
export const stickerPacks = pgTable('sticker_packs', {
    id: text('id').primaryKey(),
    name: text('name').notNull(),
    ownerUid: text('owner_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
    stickerUrls: jsonb('sticker_urls').$type().default([]).notNull(),
    createdAt: timestamp('created_at').defaultNow().notNull(),
});
