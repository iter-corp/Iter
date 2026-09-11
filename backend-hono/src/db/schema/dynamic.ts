import { mysqlTable, text, timestamp, boolean, json, varchar, int } from 'drizzle-orm/mysql-core';

export const appConfigs = mysqlTable('app_configs', {
  id: varchar('id', { length: 64 }).primaryKey().default('app'), // single singleton row 'app'
  storiesEnabled: boolean('stories_enabled').default(true).notNull(),
  repostsEnabled: boolean('reposts_enabled').default(true).notNull(),
  translateEnabled: boolean('translate_enabled').default(true).notNull(),
  maintenanceMode: boolean('maintenance_mode').default(false).notNull(),
  maintenanceMessage: text('maintenance_message').notNull(),
  minAppVersion: varchar('min_app_version', { length: 32 }).default('1.0.0').notNull(),
  announcement: text('announcement').notNull(),
  contactEmail: varchar('contact_email', { length: 191 }).default('').notNull(),
  iosAppStoreUrl: text('ios_app_store_url'),
  androidPlayStoreUrl: text('android_play_store_url'),
  eventTypes: json('event_types').$type<string[]>().default([
    'Scholarship', 'Internship', 'Research', 'Conference',
    'Summer Program', 'Competition', 'Leadership', 'Youth Summit', 'other'
  ]).notNull(),
  profileProfessionOptions: json('profile_profession_options').$type<string[]>().default([
    'Student', 'Software Engineer', 'Designer', 'Doctor', 'Teacher',
    'Lawyer', 'Accountant', 'Researcher', 'Entrepreneur', 'Other'
  ]).notNull(),
  profileFieldOptions: json('profile_field_options').$type<string[]>().default([
    'Computer Science', 'Medicine', 'Engineering', 'Business',
    'Arts & Humanities', 'Law', 'Natural Sciences', 'Social Sciences', 'Other'
  ]).notNull(),
  profileAcademicLevelOptions: json('profile_academic_level_options').$type<string[]>().default([
    'High School', 'Bachelor', 'Master', 'PhD', 'Self-taught', 'Other'
  ]).notNull(),
  profileGoalOptions: json('profile_goal_options').$type<string[]>().default([
    'Internships', 'Scholarships', 'Conferences', 'Research', 'Networking', 'Local events'
  ]).notNull(),
  profanityWordsEn: json('profanity_words_en').$type<string[]>().default([]).notNull(),
  featureFlags: json('feature_flags').$type<Record<string, boolean>>().default({
    'enable_ai_translation': true,
    'enable_polls': true,
    'enable_event_registration': true,
    'enable_voice_notes': true,
    'enable_stickers': true,
    'enable_location_pin': true
  }).notNull(),
  metadata: json('metadata').$type<Record<string, unknown>>().default({}).notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});

// Server-Driven UI (SDUI) Screens & Layout Blocks
export const sduiScreens = mysqlTable('sdui_screens', {
  id: varchar('id', { length: 128 }).primaryKey(), // e.g. 'home_top', 'explore_banner', 'announcement_modal'
  title: varchar('title', { length: 255 }).notNull(),
  description: text('description'),
  version: int('version').default(1).notNull(),
  active: boolean('active').default(true).notNull(),
  layout: json('layout').$type<{
    type: 'vertical_stack' | 'horizontal_carousel' | 'banner' | 'modal' | 'custom';
    blocks: Array<{
      id: string;
      type: 'card' | 'banner' | 'announcement' | 'carousel' | 'button' | 'html';
      title?: string;
      subtitle?: string;
      imageUrl?: string;
      backgroundColor?: string;
      textColor?: string;
      action?: {
        type: 'navigate' | 'open_url' | 'share' | 'dismiss';
        target?: string; // route path or url
        params?: Record<string, unknown>;
      };
      metadata?: Record<string, unknown>;
    }>;
  }>().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});

// Dynamic Enums & Dropdowns for client forms
export const dynamicEnums = mysqlTable('dynamic_enums', {
  id: varchar('id', { length: 128 }).primaryKey(), // e.g. 'event_categories', 'report_reasons'
  name: varchar('name', { length: 128 }).notNull(),
  items: json('items').$type<Array<{ label: string; value: string; icon?: string; badge?: string }>>().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});
