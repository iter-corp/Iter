import { mysqlTable, text, timestamp, boolean, int, json, bigint, varchar, uniqueIndex } from 'drizzle-orm/mysql-core';
import crypto from 'crypto';
export const users = mysqlTable('users', {
    id: varchar('id', { length: 128 }).primaryKey(), // UID string or UUID
    email: varchar('email', { length: 191 }).notNull().unique(),
    emailVerified: boolean('email_verified').default(false).notNull(),
    passwordHash: text('password_hash'), // Nullable for OAuth-only users
    googleId: varchar('google_id', { length: 191 }),
    appleId: varchar('apple_id', { length: 191 }),
    username: varchar('username', { length: 64 }),
    usernameLower: varchar('username_lower', { length: 64 }),
    handle: varchar('handle', { length: 64 }),
    bio: text('bio'),
    avatarUrl: text('avatar_url'),
    coverUrl: text('cover_url'),
    gender: varchar('gender', { length: 32 }),
    role: varchar('role', { length: 32 }).default('user').notNull(), // 'user' | 'org_admin' | 'admin'
    suspended: boolean('suspended').default(false).notNull(),
    suspendedAt: timestamp('suspended_at'),
    suspendedBy: varchar('suspended_by', { length: 128 }),
    isPrivate: boolean('is_private').default(false).notNull(),
    appIntroSeen: boolean('app_intro_seen').default(false).notNull(),
    followersCount: int('followers_count').default(0).notNull(),
    followingCount: int('following_count').default(0).notNull(),
    postsCount: int('posts_count').default(0).notNull(),
    profession: varchar('profession', { length: 128 }),
    field: varchar('field', { length: 128 }),
    academicLevel: varchar('academic_level', { length: 128 }),
    goals: json('goals').$type().default([]).notNull(),
    eventNotifPrefs: json('event_notif_prefs').$type().default({ mode: 'all', types: [], countries: [] }).notNull(),
    blockedUsers: json('blocked_users').$type().default([]).notNull(),
    metadata: json('metadata').$type().default({}).notNull(),
    createdAt: timestamp('created_at').defaultNow().notNull(),
    updatedAt: timestamp('updated_at').defaultNow().notNull(),
    deletedAt: timestamp('deleted_at'),
}, (table) => [
    uniqueIndex('users_username_lower_idx').on(table.usernameLower),
]);
export const sessions = mysqlTable('sessions', {
    id: varchar('id', { length: 128 }).primaryKey().$defaultFn(() => crypto.randomUUID()),
    userId: varchar('user_id', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    refreshToken: varchar('refresh_token', { length: 512 }).notNull().unique(),
    userAgent: text('user_agent'),
    ipAddress: varchar('ip_address', { length: 64 }),
    expiresAt: timestamp('expires_at').notNull(),
    createdAt: timestamp('created_at').defaultNow().notNull(),
});
export const blacklist = mysqlTable('blacklist', {
    id: bigint('id', { mode: 'number', unsigned: true }).autoincrement().primaryKey(),
    emailOrDomain: varchar('email_or_domain', { length: 191 }).notNull().unique(),
    reason: text('reason'),
    createdAt: timestamp('created_at').defaultNow().notNull(),
});
export const profileVisitors = mysqlTable('profile_visitors', {
    id: bigint('id', { mode: 'number', unsigned: true }).autoincrement().primaryKey(),
    ownerUid: varchar('owner_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    visitorUid: varchar('visitor_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    visitCount: int('visit_count').default(1).notNull(),
    lastVisitedAt: timestamp('last_visited_at').defaultNow().notNull(),
}, (table) => [
    uniqueIndex('profile_visitors_pair_idx').on(table.ownerUid, table.visitorUid),
]);
export const userReports = mysqlTable('user_reports', {
    id: varchar('id', { length: 128 }).primaryKey(), // `${targetUid}_${reporterUid}`
    targetUid: varchar('target_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    targetUsername: varchar('target_username', { length: 64 }).notNull(),
    targetAvatar: text('target_avatar'),
    reporterUid: varchar('reporter_uid', { length: 128 }).notNull().references(() => users.id, { onDelete: 'cascade' }),
    reporterUsername: varchar('reporter_username', { length: 64 }).notNull(),
    reason: varchar('reason', { length: 255 }).notNull(),
    details: text('details'),
    resolved: boolean('resolved').default(false).notNull(),
    resolvedAt: timestamp('resolved_at'),
    createdAt: timestamp('created_at').defaultNow().notNull(),
});
