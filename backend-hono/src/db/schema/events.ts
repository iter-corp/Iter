import { pgTable, text, timestamp, integer, boolean, jsonb, doublePrecision, uniqueIndex } from 'drizzle-orm/pg-core';
import { users } from './users.js';

export const events = pgTable('events', {
  id: text('id').primaryKey(),
  title: text('title').notNull(),
  description: text('description').default('').notNull(),
  location: text('location').default('').notNull(),
  locationCountry: text('location_country').default('').notNull(), // lowercased country
  eventType: text('event_type').notNull(), // 'Scholarship', 'Internship', etc.
  coverImageUrl: text('cover_image_url'),
  linkUrl: text('link_url'),
  startDate: timestamp('start_date'),
  endDate: timestamp('end_date'),
  capacity: integer('capacity'),
  authorUid: text('author_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  authorUsername: text('author_username').notNull(),
  authorAvatar: text('author_avatar'),
  isOnline: boolean('is_online').default(false).notNull(),
  lat: doublePrecision('lat'),
  lng: doublePrecision('lng'),
  notifiedUserCount: integer('notified_user_count').default(0).notNull(),
  notifiedAt: timestamp('notified_at'),
  metadata: jsonb('metadata').$type<Record<string, unknown>>().default({}).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});

export const eventRegistrations = pgTable('event_registrations', {
  id: text('id').primaryKey(), // `${eventId}_${userUid}`
  eventId: text('event_id').notNull().references(() => events.id, { onDelete: 'cascade' }),
  eventTitle: text('event_title').notNull(),
  userUid: text('user_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  name: text('name').notNull(),
  email: text('email').notNull(),
  phone: text('phone').notNull(),
  countryCode: text('country_code').notNull(),
  status: text('status').default('pending').notNull(), // 'pending' | 'approved' | 'rejected'
  reviewedAt: timestamp('reviewed_at'),
  reviewedBy: text('reviewed_by'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
}, (table) => [
  uniqueIndex('event_registrations_event_user_idx').on(table.eventId, table.userUid),
]);

export const eventChatMessages = pgTable('event_chat_messages', {
  id: text('id').primaryKey(),
  eventId: text('event_id').notNull().references(() => events.id, { onDelete: 'cascade' }),
  senderUid: text('sender_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
  senderUsername: text('sender_username').notNull(),
  senderAvatar: text('sender_avatar'),
  text: text('text').default('').notNull(),
  imageUrl: text('image_url'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});
