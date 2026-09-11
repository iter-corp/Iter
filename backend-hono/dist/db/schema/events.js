import { mysqlTable, text, timestamp, int, boolean, json, double, varchar, uniqueIndex } from 'drizzle-orm/mysql-core';
import { users } from './users.js';
export const events = mysqlTable('events', {
    id: varchar('id', { length: 128 }).primaryKey(),
    title: varchar('title', { length: 255 }).notNull(),
    description: text('description').notNull(),
    location: varchar('location', { length: 255 }).default('').notNull(),
    locationCountry: varchar('location_country', { length: 128 }).default('').notNull(),
    eventType: varchar('event_type', { length: 64 }).notNull(),
    coverImageUrl: text('cover_image_url'),
    linkUrl: text('link_url'),
    startDate: timestamp('start_date'),
    endDate: timestamp('end_date'),
    capacity: int('capacity'),
    authorUid: varchar('author_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    authorUsername: varchar('author_username', { length: 64 }).notNull(),
    authorAvatar: text('author_avatar'),
    isOnline: boolean('is_online').default(false).notNull(),
    lat: double('lat'),
    lng: double('lng'),
    notifiedUserCount: int('notified_user_count').default(0).notNull(),
    notifiedAt: timestamp('notified_at'),
    metadata: json('metadata').$type().default({}).notNull(),
    createdAt: timestamp('created_at').defaultNow().notNull(),
    updatedAt: timestamp('updated_at').defaultNow().notNull(),
});
export const eventRegistrations = mysqlTable('event_registrations', {
    id: varchar('id', { length: 255 }).primaryKey(), // `${eventId}_${userUid}`
    eventId: varchar('event_id', { length: 128 }).notNull().references(() => events.id, { onDelete: 'cascade' }),
    eventTitle: varchar('event_title', { length: 255 }).notNull(),
    userUid: varchar('user_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    name: varchar('name', { length: 128 }).notNull(),
    email: varchar('email', { length: 191 }).notNull(),
    phone: varchar('phone', { length: 64 }).notNull(),
    countryCode: varchar('country_code', { length: 16 }).notNull(),
    status: varchar('status', { length: 32 }).default('pending').notNull(), // 'pending' | 'approved' | 'rejected'
    reviewedAt: timestamp('reviewed_at'),
    reviewedBy: varchar('reviewed_by', { length: 128 }),
    createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
    uniqueIndex('event_registrations_event_user_idx').on(table.eventId, table.userUid),
]);
export const eventChatMessages = mysqlTable('event_chat_messages', {
    id: varchar('id', { length: 128 }).primaryKey(),
    eventId: varchar('event_id', { length: 128 }).notNull().references(() => events.id, { onDelete: 'cascade' }),
    senderUid: varchar('sender_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    senderUsername: varchar('sender_username', { length: 64 }).notNull(),
    senderAvatar: text('sender_avatar'),
    text: text('text').notNull(),
    imageUrl: text('image_url'),
    createdAt: timestamp('created_at').defaultNow().notNull(),
});
