import { pgTable, text, timestamp, boolean, integer, jsonb, serial, uuid, uniqueIndex } from 'drizzle-orm/pg-core';
export const users = pgTable('users', {
    id: text('id').primaryKey(), // UID string or UUID
    email: text('email').notNull().unique(),
    emailVerified: boolean('email_verified').default(false).notNull(),
    passwordHash: text('password_hash'), // Nullable for OAuth-only users
    googleId: text('google_id'),
    appleId: text('apple_id'),
    username: text('username'),
    usernameLower: text('username_lower'),
    handle: text('handle'),
    bio: text('bio').default('').notNull(),
    avatarUrl: text('avatar_url'),
    coverUrl: text('cover_url'),
    gender: text('gender'),
    role: text('role').default('user').notNull(), // 'user' | 'org_admin' | 'admin'
    suspended: boolean('suspended').default(false).notNull(),
    suspendedAt: timestamp('suspended_at'),
    suspendedBy: text('suspended_by'),
    isPrivate: boolean('is_private').default(false).notNull(),
    appIntroSeen: boolean('app_intro_seen').default(false).notNull(),
    followersCount: integer('followers_count').default(0).notNull(),
    followingCount: integer('following_count').default(0).notNull(),
    postsCount: integer('posts_count').default(0).notNull(),
    profession: text('profession'),
    field: text('field'),
    academicLevel: text('academic_level'),
    goals: jsonb('goals').$type().default([]).notNull(),
    eventNotifPrefs: jsonb('event_notif_prefs').$type().default({ mode: 'all', types: [], countries: [] }).notNull(),
    blockedUsers: jsonb('blocked_users').$type().default([]).notNull(),
    metadata: jsonb('metadata').$type().default({}).notNull(),
    createdAt: timestamp('created_at').defaultNow().notNull(),
    updatedAt: timestamp('updated_at').defaultNow().notNull(),
    deletedAt: timestamp('deleted_at'),
}, (table) => [
    uniqueIndex('users_username_lower_idx').on(table.usernameLower),
]);
export const sessions = pgTable('sessions', {
    id: uuid('id').defaultRandom().primaryKey(),
    userId: text('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
    refreshToken: text('refresh_token').notNull().unique(),
    userAgent: text('user_agent'),
    ipAddress: text('ip_address'),
    expiresAt: timestamp('expires_at').notNull(),
    createdAt: timestamp('created_at').defaultNow().notNull(),
});
export const blacklist = pgTable('blacklist', {
    id: serial('id').primaryKey(),
    emailOrDomain: text('email_or_domain').notNull().unique(),
    reason: text('reason'),
    createdAt: timestamp('created_at').defaultNow().notNull(),
});
export const profileVisitors = pgTable('profile_visitors', {
    id: serial('id').primaryKey(),
    ownerUid: text('owner_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
    visitorUid: text('visitor_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
    visitCount: integer('visit_count').default(1).notNull(),
    lastVisitedAt: timestamp('last_visited_at').defaultNow().notNull(),
}, (table) => [
    uniqueIndex('profile_visitors_pair_idx').on(table.ownerUid, table.visitorUid),
]);
export const userReports = pgTable('user_reports', {
    id: text('id').primaryKey(), // `${targetUid}_${reporterUid}`
    targetUid: text('target_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
    targetUsername: text('target_username').notNull(),
    targetAvatar: text('target_avatar'),
    reporterUid: text('reporter_uid').notNull().references(() => users.id, { onDelete: 'cascade' }),
    reporterUsername: text('reporter_username').notNull(),
    reason: text('reason').notNull(),
    details: text('details'),
    resolved: boolean('resolved').default(false).notNull(),
    resolvedAt: timestamp('resolved_at'),
    createdAt: timestamp('created_at').defaultNow().notNull(),
});
