import { pgTable, text, timestamp, boolean, jsonb, integer } from 'drizzle-orm/pg-core';
export const appConfigs = pgTable('app_configs', {
    id: text('id').primaryKey().default('app'), // single singleton row 'app'
    storiesEnabled: boolean('stories_enabled').default(true).notNull(),
    repostsEnabled: boolean('reposts_enabled').default(true).notNull(),
    translateEnabled: boolean('translate_enabled').default(true).notNull(),
    maintenanceMode: boolean('maintenance_mode').default(false).notNull(),
    maintenanceMessage: text('maintenance_message').default('Iter is temporarily under scheduled maintenance. Please check back shortly.').notNull(),
    minAppVersion: text('min_app_version').default('1.0.0').notNull(),
    announcement: text('announcement').default('').notNull(),
    contactEmail: text('contact_email').default('').notNull(),
    iosAppStoreUrl: text('ios_app_store_url').default('').notNull(),
    androidPlayStoreUrl: text('android_play_store_url').default('').notNull(),
    eventTypes: jsonb('event_types').$type().default([
        'Scholarship', 'Internship', 'Research', 'Conference',
        'Summer Program', 'Competition', 'Leadership', 'Youth Summit', 'other'
    ]).notNull(),
    profileProfessionOptions: jsonb('profile_profession_options').$type().default([
        'Student', 'Software Engineer', 'Designer', 'Doctor', 'Teacher',
        'Lawyer', 'Accountant', 'Researcher', 'Entrepreneur', 'Other'
    ]).notNull(),
    profileFieldOptions: jsonb('profile_field_options').$type().default([
        'Computer Science', 'Medicine', 'Engineering', 'Business',
        'Arts & Humanities', 'Law', 'Natural Sciences', 'Social Sciences', 'Other'
    ]).notNull(),
    profileAcademicLevelOptions: jsonb('profile_academic_level_options').$type().default([
        'High School', 'Bachelor', 'Master', 'PhD', 'Self-taught', 'Other'
    ]).notNull(),
    profileGoalOptions: jsonb('profile_goal_options').$type().default([
        'Internships', 'Scholarships', 'Conferences', 'Research', 'Networking', 'Local events'
    ]).notNull(),
    profanityWordsEn: jsonb('profanity_words_en').$type().default([]).notNull(),
    featureFlags: jsonb('feature_flags').$type().default({
        'enable_ai_translation': true,
        'enable_polls': true,
        'enable_event_registration': true,
        'enable_voice_notes': true,
        'enable_stickers': true,
        'enable_location_pin': true
    }).notNull(),
    metadata: jsonb('metadata').$type().default({}).notNull(),
    updatedAt: timestamp('updated_at').defaultNow().notNull(),
});
// Server-Driven UI (SDUI) Screens & Layout Blocks
export const sduiScreens = pgTable('sdui_screens', {
    id: text('id').primaryKey(), // e.g. 'home_top', 'explore_banner', 'announcement_modal'
    title: text('title').notNull(),
    description: text('description'),
    version: integer('version').default(1).notNull(),
    active: boolean('active').default(true).notNull(),
    layout: jsonb('layout').$type().notNull(),
    updatedAt: timestamp('updated_at').defaultNow().notNull(),
});
// Dynamic Enums & Dropdowns for client forms
export const dynamicEnums = pgTable('dynamic_enums', {
    id: text('id').primaryKey(), // e.g. 'event_categories', 'report_reasons'
    name: text('name').notNull(),
    items: jsonb('items').$type().notNull(),
    updatedAt: timestamp('updated_at').defaultNow().notNull(),
});
