CREATE TABLE `blacklist` (
	`id` bigint unsigned NOT NULL AUTO_INCREMENT,
	`email_or_domain` varchar(191) NOT NULL,
	`reason` text,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `blacklist_id` PRIMARY KEY(`id`),
	CONSTRAINT `blacklist_email_or_domain_unique` UNIQUE(`email_or_domain`)
);
--> statement-breakpoint
CREATE TABLE `profile_visitors` (
	`id` bigint unsigned NOT NULL AUTO_INCREMENT,
	`owner_uid` varchar(128) NOT NULL,
	`visitor_uid` varchar(128) NOT NULL,
	`visit_count` int NOT NULL DEFAULT 1,
	`last_visited_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `profile_visitors_id` PRIMARY KEY(`id`),
	CONSTRAINT `profile_visitors_pair_idx` UNIQUE(`owner_uid`,`visitor_uid`)
);
--> statement-breakpoint
CREATE TABLE `sessions` (
	`id` varchar(128) NOT NULL,
	`user_id` varchar(128) NOT NULL,
	`refresh_token` varchar(512) NOT NULL,
	`user_agent` text,
	`ip_address` varchar(64),
	`expires_at` timestamp NOT NULL,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `sessions_id` PRIMARY KEY(`id`),
	CONSTRAINT `sessions_refresh_token_unique` UNIQUE(`refresh_token`)
);
--> statement-breakpoint
CREATE TABLE `user_reports` (
	`id` varchar(128) NOT NULL,
	`target_uid` varchar(128) NOT NULL,
	`target_username` varchar(64) NOT NULL,
	`target_avatar` text,
	`reporter_uid` varchar(128) NOT NULL,
	`reporter_username` varchar(64) NOT NULL,
	`reason` varchar(255) NOT NULL,
	`details` text,
	`resolved` boolean NOT NULL DEFAULT false,
	`resolved_at` timestamp,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `user_reports_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `users` (
	`id` varchar(128) NOT NULL,
	`email` varchar(191) NOT NULL,
	`email_verified` boolean NOT NULL DEFAULT false,
	`password_hash` text,
	`google_id` varchar(191),
	`apple_id` varchar(191),
	`username` varchar(64),
	`username_lower` varchar(64),
	`handle` varchar(64),
	`bio` text,
	`avatar_url` text,
	`cover_url` text,
	`gender` varchar(32),
	`role` varchar(32) NOT NULL DEFAULT 'user',
	`suspended` boolean NOT NULL DEFAULT false,
	`suspended_at` timestamp,
	`suspended_by` varchar(128),
	`is_private` boolean NOT NULL DEFAULT false,
	`app_intro_seen` boolean NOT NULL DEFAULT false,
	`followers_count` int NOT NULL DEFAULT 0,
	`following_count` int NOT NULL DEFAULT 0,
	`posts_count` int NOT NULL DEFAULT 0,
	`profession` varchar(128),
	`field` varchar(128),
	`academic_level` varchar(128),
	`goals` json NOT NULL DEFAULT ('[]'),
	`event_notif_prefs` json NOT NULL DEFAULT ('{"mode":"all","types":[],"countries":[]}'),
	`blocked_users` json NOT NULL DEFAULT ('[]'),
	`metadata` json NOT NULL DEFAULT ('{}'),
	`created_at` timestamp NOT NULL DEFAULT (now()),
	`updated_at` timestamp NOT NULL DEFAULT (now()),
	`deleted_at` timestamp,
	CONSTRAINT `users_id` PRIMARY KEY(`id`),
	CONSTRAINT `users_email_unique` UNIQUE(`email`),
	CONSTRAINT `users_username_lower_idx` UNIQUE(`username_lower`)
);
--> statement-breakpoint
CREATE TABLE `blocks` (
	`id` varchar(255) NOT NULL,
	`blocker_uid` varchar(128) NOT NULL,
	`blocked_uid` varchar(128) NOT NULL,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `blocks_id` PRIMARY KEY(`id`),
	CONSTRAINT `blocks_blocker_blocked_idx` UNIQUE(`blocker_uid`,`blocked_uid`)
);
--> statement-breakpoint
CREATE TABLE `follows` (
	`id` varchar(255) NOT NULL,
	`follower_uid` varchar(128) NOT NULL,
	`target_uid` varchar(128) NOT NULL,
	`status` varchar(32) NOT NULL DEFAULT 'active',
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `follows_id` PRIMARY KEY(`id`),
	CONSTRAINT `follows_follower_target_idx` UNIQUE(`follower_uid`,`target_uid`)
);
--> statement-breakpoint
CREATE TABLE `post_likes` (
	`id` varchar(255) NOT NULL,
	`post_id` varchar(128) NOT NULL,
	`uid` varchar(128) NOT NULL,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `post_likes_id` PRIMARY KEY(`id`),
	CONSTRAINT `post_likes_pair_idx` UNIQUE(`post_id`,`uid`)
);
--> statement-breakpoint
CREATE TABLE `post_reports` (
	`id` varchar(255) NOT NULL,
	`post_id` varchar(128) NOT NULL,
	`post_author_uid` varchar(128) NOT NULL,
	`post_author_username` varchar(64) NOT NULL,
	`post_author_avatar` text,
	`post_caption` text NOT NULL,
	`reporter_uid` varchar(128) NOT NULL,
	`reporter_username` varchar(64) NOT NULL,
	`reason` varchar(255) NOT NULL,
	`details` text,
	`is_qa` boolean NOT NULL DEFAULT false,
	`resolved` boolean NOT NULL DEFAULT false,
	`resolved_at` timestamp,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `post_reports_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `post_reposts` (
	`id` varchar(255) NOT NULL,
	`post_id` varchar(128) NOT NULL,
	`uid` varchar(128) NOT NULL,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `post_reposts_id` PRIMARY KEY(`id`),
	CONSTRAINT `post_reposts_pair_idx` UNIQUE(`post_id`,`uid`)
);
--> statement-breakpoint
CREATE TABLE `post_saves` (
	`id` varchar(255) NOT NULL,
	`post_id` varchar(128) NOT NULL,
	`uid` varchar(128) NOT NULL,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `post_saves_id` PRIMARY KEY(`id`),
	CONSTRAINT `post_saves_pair_idx` UNIQUE(`post_id`,`uid`)
);
--> statement-breakpoint
CREATE TABLE `posts` (
	`id` varchar(128) NOT NULL,
	`author_uid` varchar(128) NOT NULL,
	`author_username` varchar(64) NOT NULL,
	`author_avatar` text,
	`caption` text NOT NULL,
	`image_urls` json NOT NULL DEFAULT ('[]'),
	`video_urls` json NOT NULL DEFAULT ('[]'),
	`likes_count` int NOT NULL DEFAULT 0,
	`comments_count` int NOT NULL DEFAULT 0,
	`is_private` boolean NOT NULL DEFAULT false,
	`post_type` varchar(32) NOT NULL DEFAULT 'regular',
	`discuss_kind` varchar(32) NOT NULL DEFAULT 'question',
	`source_post_id` varchar(128),
	`post_place_name` varchar(255),
	`post_place_city` varchar(128),
	`post_lat` double,
	`post_lng` double,
	`post_location_exact` boolean NOT NULL DEFAULT false,
	`place_search_key` varchar(255),
	`metadata` json NOT NULL DEFAULT ('{}'),
	`created_at` timestamp NOT NULL DEFAULT (now()),
	`updated_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `posts_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `comment_helpful_votes` (
	`id` varchar(255) NOT NULL,
	`comment_id` varchar(128) NOT NULL,
	`uid` varchar(128) NOT NULL,
	`is_helpful` boolean NOT NULL,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `comment_helpful_votes_id` PRIMARY KEY(`id`),
	CONSTRAINT `comment_helpful_votes_pair_idx` UNIQUE(`comment_id`,`uid`)
);
--> statement-breakpoint
CREATE TABLE `comment_likes` (
	`id` varchar(255) NOT NULL,
	`comment_id` varchar(128) NOT NULL,
	`uid` varchar(128) NOT NULL,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `comment_likes_id` PRIMARY KEY(`id`),
	CONSTRAINT `comment_likes_pair_idx` UNIQUE(`comment_id`,`uid`)
);
--> statement-breakpoint
CREATE TABLE `comment_reports` (
	`id` varchar(255) NOT NULL,
	`comment_id` varchar(128) NOT NULL,
	`post_id` varchar(128) NOT NULL,
	`comment_author_uid` varchar(128) NOT NULL,
	`comment_author_username` varchar(64) NOT NULL,
	`comment_text` text NOT NULL,
	`reporter_uid` varchar(128) NOT NULL,
	`reporter_username` varchar(64) NOT NULL,
	`reason` varchar(255) NOT NULL,
	`resolved` boolean NOT NULL DEFAULT false,
	`resolved_at` timestamp,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `comment_reports_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `comments` (
	`id` varchar(128) NOT NULL,
	`post_id` varchar(128) NOT NULL,
	`author_uid` varchar(128) NOT NULL,
	`author_username` varchar(64) NOT NULL,
	`author_avatar` text,
	`text` text NOT NULL,
	`parent_comment_id` varchar(128),
	`reply_to_username` varchar(64),
	`helpful_count` int NOT NULL DEFAULT 0,
	`unhelpful_count` int NOT NULL DEFAULT 0,
	`likes_count` int NOT NULL DEFAULT 0,
	`profanity_filtered` boolean NOT NULL DEFAULT false,
	`sender_only` boolean NOT NULL DEFAULT false,
	`marked_helpful` boolean NOT NULL DEFAULT false,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	`updated_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `comments_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `stories` (
	`id` varchar(128) NOT NULL,
	`author_uid` varchar(128) NOT NULL,
	`author_username` varchar(64) NOT NULL,
	`author_avatar` text,
	`image_url` text NOT NULL,
	`video_url` text,
	`video_trim_start_ms` int,
	`video_trim_end_ms` int,
	`text_content` text,
	`background_color` int,
	`text_color` int,
	`text_border_style` varchar(64),
	`shared_post_id` varchar(128),
	`shared_event_id` varchar(128),
	`shared_event_title` varchar(255),
	`overlays` json NOT NULL DEFAULT ('[]'),
	`likes_count` int NOT NULL DEFAULT 0,
	`comments_count` int NOT NULL DEFAULT 0,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	`expires_at` timestamp NOT NULL,
	CONSTRAINT `stories_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `story_likes` (
	`id` varchar(255) NOT NULL,
	`story_id` varchar(128) NOT NULL,
	`uid` varchar(128) NOT NULL,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `story_likes_id` PRIMARY KEY(`id`),
	CONSTRAINT `story_likes_pair_idx` UNIQUE(`story_id`,`uid`)
);
--> statement-breakpoint
CREATE TABLE `story_viewers` (
	`id` varchar(255) NOT NULL,
	`story_id` varchar(128) NOT NULL,
	`uid` varchar(128) NOT NULL,
	`username` varchar(64) NOT NULL,
	`avatar_url` text,
	`viewed_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `story_viewers_id` PRIMARY KEY(`id`),
	CONSTRAINT `story_viewers_pair_idx` UNIQUE(`story_id`,`uid`)
);
--> statement-breakpoint
CREATE TABLE `chats` (
	`id` varchar(128) NOT NULL,
	`kind` varchar(32) NOT NULL DEFAULT 'direct',
	`group_name` varchar(128) NOT NULL DEFAULT '',
	`group_avatar_url` text,
	`admin_uid` varchar(128) NOT NULL DEFAULT '',
	`last_message` text NOT NULL,
	`last_message_sender_uid` varchar(128) NOT NULL DEFAULT '',
	`last_time` timestamp NOT NULL DEFAULT (now()),
	`participants` json NOT NULL DEFAULT ('[]'),
	`accepted_by` json NOT NULL DEFAULT ('[]'),
	`muted_for` json NOT NULL DEFAULT ('[]'),
	`unread_counts` json NOT NULL DEFAULT ('{}'),
	`user_data` json NOT NULL DEFAULT ('{}'),
	`metadata` json NOT NULL DEFAULT ('{}'),
	`created_at` timestamp NOT NULL DEFAULT (now()),
	`updated_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `chats_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `message_reactions` (
	`id` varchar(255) NOT NULL,
	`message_id` varchar(128) NOT NULL,
	`uid` varchar(128) NOT NULL,
	`reaction` varchar(64) NOT NULL,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `message_reactions_id` PRIMARY KEY(`id`),
	CONSTRAINT `message_reactions_pair_idx` UNIQUE(`message_id`,`uid`)
);
--> statement-breakpoint
CREATE TABLE `messages` (
	`id` varchar(128) NOT NULL,
	`chat_id` varchar(128) NOT NULL,
	`sender_uid` varchar(128) NOT NULL,
	`text` text NOT NULL,
	`sender_only_text` text,
	`image_url` text,
	`video_url` text,
	`file_url` text,
	`file_name` varchar(255),
	`file_mime_type` varchar(128),
	`file_size_bytes` int,
	`voice_url` text,
	`voice_duration_ms` int,
	`voice_transcript` text,
	`sticker_url` text,
	`sticker_pack_id` varchar(128),
	`shared_post_id` varchar(128),
	`shared_event_id` varchar(128),
	`story_id` varchar(128),
	`story_image_url` text,
	`reply_to_id` varchar(128),
	`reply_to_text` text,
	`reply_to_sender_uid` varchar(128),
	`location_lat` double,
	`location_lng` double,
	`location_label` varchar(255),
	`seen_by` json NOT NULL DEFAULT ('[]'),
	`visible_to_uids` json NOT NULL DEFAULT ('[]'),
	`deleted_for_uids` json NOT NULL DEFAULT ('[]'),
	`deleted_for_everyone` boolean NOT NULL DEFAULT false,
	`profanity_filtered` boolean NOT NULL DEFAULT false,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `messages_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `event_chat_messages` (
	`id` varchar(128) NOT NULL,
	`event_id` varchar(128) NOT NULL,
	`sender_uid` varchar(128) NOT NULL,
	`sender_username` varchar(64) NOT NULL,
	`sender_avatar` text,
	`text` text NOT NULL,
	`image_url` text,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `event_chat_messages_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `event_registrations` (
	`id` varchar(255) NOT NULL,
	`event_id` varchar(128) NOT NULL,
	`event_title` varchar(255) NOT NULL,
	`user_uid` varchar(128) NOT NULL,
	`name` varchar(128) NOT NULL,
	`email` varchar(191) NOT NULL,
	`phone` varchar(64) NOT NULL,
	`country_code` varchar(16) NOT NULL,
	`status` varchar(32) NOT NULL DEFAULT 'pending',
	`reviewed_at` timestamp,
	`reviewed_by` varchar(128),
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `event_registrations_id` PRIMARY KEY(`id`),
	CONSTRAINT `event_registrations_event_user_idx` UNIQUE(`event_id`,`user_uid`)
);
--> statement-breakpoint
CREATE TABLE `events` (
	`id` varchar(128) NOT NULL,
	`title` varchar(255) NOT NULL,
	`description` text NOT NULL,
	`location` varchar(255) NOT NULL DEFAULT '',
	`location_country` varchar(128) NOT NULL DEFAULT '',
	`event_type` varchar(64) NOT NULL,
	`cover_image_url` text,
	`link_url` text,
	`start_date` timestamp,
	`end_date` timestamp,
	`capacity` int,
	`author_uid` varchar(128) NOT NULL,
	`author_username` varchar(64) NOT NULL,
	`author_avatar` text,
	`is_online` boolean NOT NULL DEFAULT false,
	`lat` double,
	`lng` double,
	`notified_user_count` int NOT NULL DEFAULT 0,
	`notified_at` timestamp,
	`metadata` json NOT NULL DEFAULT ('{}'),
	`created_at` timestamp NOT NULL DEFAULT (now()),
	`updated_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `events_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `poll_votes` (
	`id` varchar(255) NOT NULL,
	`poll_id` varchar(128) NOT NULL,
	`uid` varchar(128) NOT NULL,
	`option_index` int NOT NULL,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `poll_votes_id` PRIMARY KEY(`id`),
	CONSTRAINT `poll_votes_pair_idx` UNIQUE(`poll_id`,`uid`)
);
--> statement-breakpoint
CREATE TABLE `polls` (
	`id` varchar(128) NOT NULL,
	`question` text NOT NULL,
	`options` json NOT NULL DEFAULT ('[]'),
	`created_by_uid` varchar(128) NOT NULL,
	`visibility` varchar(32) NOT NULL DEFAULT 'public',
	`closed` boolean NOT NULL DEFAULT false,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `polls_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `fcm_tokens` (
	`id` bigint unsigned NOT NULL AUTO_INCREMENT,
	`uid` varchar(128) NOT NULL,
	`token` varchar(512) NOT NULL,
	`device_type` varchar(32) NOT NULL DEFAULT 'unknown',
	`created_at` timestamp NOT NULL DEFAULT (now()),
	`updated_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `fcm_tokens_id` PRIMARY KEY(`id`),
	CONSTRAINT `fcm_tokens_token_unique` UNIQUE(`token`),
	CONSTRAINT `fcm_tokens_uid_token_idx` UNIQUE(`uid`,`token`)
);
--> statement-breakpoint
CREATE TABLE `notifications` (
	`id` varchar(128) NOT NULL,
	`target_uid` varchar(128) NOT NULL,
	`type` varchar(64) NOT NULL,
	`actor_uid` varchar(128) NOT NULL DEFAULT '',
	`target_id` varchar(128),
	`comment_id` varchar(128),
	`title` varchar(255),
	`subtitle` text,
	`status` varchar(64),
	`read` boolean NOT NULL DEFAULT false,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `notifications_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `app_configs` (
	`id` varchar(64) NOT NULL DEFAULT 'app',
	`stories_enabled` boolean NOT NULL DEFAULT true,
	`reposts_enabled` boolean NOT NULL DEFAULT true,
	`translate_enabled` boolean NOT NULL DEFAULT true,
	`maintenance_mode` boolean NOT NULL DEFAULT false,
	`maintenance_message` text NOT NULL,
	`min_app_version` varchar(32) NOT NULL DEFAULT '1.0.0',
	`announcement` text NOT NULL,
	`contact_email` varchar(191) NOT NULL DEFAULT '',
	`ios_app_store_url` text,
	`android_play_store_url` text,
	`event_types` json NOT NULL DEFAULT ('["Scholarship","Internship","Research","Conference","Summer Program","Competition","Leadership","Youth Summit","other"]'),
	`profile_profession_options` json NOT NULL DEFAULT ('["Student","Software Engineer","Designer","Doctor","Teacher","Lawyer","Accountant","Researcher","Entrepreneur","Other"]'),
	`profile_field_options` json NOT NULL DEFAULT ('["Computer Science","Medicine","Engineering","Business","Arts & Humanities","Law","Natural Sciences","Social Sciences","Other"]'),
	`profile_academic_level_options` json NOT NULL DEFAULT ('["High School","Bachelor","Master","PhD","Self-taught","Other"]'),
	`profile_goal_options` json NOT NULL DEFAULT ('["Internships","Scholarships","Conferences","Research","Networking","Local events"]'),
	`profanity_words_en` json NOT NULL DEFAULT ('[]'),
	`feature_flags` json NOT NULL DEFAULT ('{"enable_ai_translation":true,"enable_polls":true,"enable_event_registration":true,"enable_voice_notes":true,"enable_stickers":true,"enable_location_pin":true}'),
	`metadata` json NOT NULL DEFAULT ('{}'),
	`updated_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `app_configs_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `dynamic_enums` (
	`id` varchar(128) NOT NULL,
	`name` varchar(128) NOT NULL,
	`items` json NOT NULL,
	`updated_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `dynamic_enums_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `sdui_screens` (
	`id` varchar(128) NOT NULL,
	`title` varchar(255) NOT NULL,
	`description` text,
	`version` int NOT NULL DEFAULT 1,
	`active` boolean NOT NULL DEFAULT true,
	`layout` json NOT NULL,
	`updated_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `sdui_screens_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `api_keys` (
	`id` varchar(128) NOT NULL,
	`provider` varchar(64) NOT NULL,
	`key` text NOT NULL,
	`active` boolean NOT NULL DEFAULT true,
	`priority` int NOT NULL DEFAULT 999,
	`status_message` text,
	`last_checked` timestamp,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	`updated_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `api_keys_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `api_logs` (
	`id` bigint unsigned NOT NULL AUTO_INCREMENT,
	`provider` varchar(64) NOT NULL,
	`key_id` varchar(128),
	`success` boolean NOT NULL,
	`was_fallback` boolean NOT NULL DEFAULT false,
	`error` text,
	`next_provider` varchar(64),
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `api_logs_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `contact_requests` (
	`id` varchar(128) NOT NULL,
	`user_uid` varchar(128) NOT NULL,
	`username` varchar(64) NOT NULL,
	`email` varchar(191) NOT NULL,
	`type` varchar(32) NOT NULL DEFAULT 'message',
	`subject` varchar(255) NOT NULL,
	`message` text NOT NULL,
	`status` varchar(32) NOT NULL DEFAULT 'open',
	`admin_notes` text,
	`replied_at` timestamp,
	`replied_by` varchar(128),
	`created_at` timestamp NOT NULL DEFAULT (now()),
	`updated_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `contact_requests_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `error_reports` (
	`id` varchar(128) NOT NULL,
	`error` text NOT NULL,
	`stack_trace` text,
	`screen` varchar(128) NOT NULL DEFAULT 'unknown',
	`app_version` varchar(64),
	`platform` varchar(32),
	`user_uid` varchar(128),
	`resolved` boolean NOT NULL DEFAULT false,
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `error_reports_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
CREATE TABLE `sticker_packs` (
	`id` varchar(128) NOT NULL,
	`name` varchar(128) NOT NULL,
	`owner_uid` varchar(128) NOT NULL,
	`sticker_urls` json NOT NULL DEFAULT ('[]'),
	`created_at` timestamp NOT NULL DEFAULT (now()),
	CONSTRAINT `sticker_packs_id` PRIMARY KEY(`id`)
);
--> statement-breakpoint
ALTER TABLE `profile_visitors` ADD CONSTRAINT `profile_visitors_owner_uid_users_id_fk` FOREIGN KEY (`owner_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `profile_visitors` ADD CONSTRAINT `profile_visitors_visitor_uid_users_id_fk` FOREIGN KEY (`visitor_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `sessions` ADD CONSTRAINT `sessions_user_id_users_id_fk` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `user_reports` ADD CONSTRAINT `user_reports_target_uid_users_id_fk` FOREIGN KEY (`target_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `user_reports` ADD CONSTRAINT `user_reports_reporter_uid_users_id_fk` FOREIGN KEY (`reporter_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `blocks` ADD CONSTRAINT `blocks_blocker_uid_users_id_fk` FOREIGN KEY (`blocker_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `blocks` ADD CONSTRAINT `blocks_blocked_uid_users_id_fk` FOREIGN KEY (`blocked_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `follows` ADD CONSTRAINT `follows_follower_uid_users_id_fk` FOREIGN KEY (`follower_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `follows` ADD CONSTRAINT `follows_target_uid_users_id_fk` FOREIGN KEY (`target_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `post_likes` ADD CONSTRAINT `post_likes_post_id_posts_id_fk` FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `post_likes` ADD CONSTRAINT `post_likes_uid_users_id_fk` FOREIGN KEY (`uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `post_reports` ADD CONSTRAINT `post_reports_post_id_posts_id_fk` FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `post_reports` ADD CONSTRAINT `post_reports_reporter_uid_users_id_fk` FOREIGN KEY (`reporter_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `post_reposts` ADD CONSTRAINT `post_reposts_post_id_posts_id_fk` FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `post_reposts` ADD CONSTRAINT `post_reposts_uid_users_id_fk` FOREIGN KEY (`uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `post_saves` ADD CONSTRAINT `post_saves_post_id_posts_id_fk` FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `post_saves` ADD CONSTRAINT `post_saves_uid_users_id_fk` FOREIGN KEY (`uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `posts` ADD CONSTRAINT `posts_author_uid_users_id_fk` FOREIGN KEY (`author_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `comment_helpful_votes` ADD CONSTRAINT `comment_helpful_votes_comment_id_comments_id_fk` FOREIGN KEY (`comment_id`) REFERENCES `comments`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `comment_helpful_votes` ADD CONSTRAINT `comment_helpful_votes_uid_users_id_fk` FOREIGN KEY (`uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `comment_likes` ADD CONSTRAINT `comment_likes_comment_id_comments_id_fk` FOREIGN KEY (`comment_id`) REFERENCES `comments`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `comment_likes` ADD CONSTRAINT `comment_likes_uid_users_id_fk` FOREIGN KEY (`uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `comment_reports` ADD CONSTRAINT `comment_reports_comment_id_comments_id_fk` FOREIGN KEY (`comment_id`) REFERENCES `comments`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `comment_reports` ADD CONSTRAINT `comment_reports_post_id_posts_id_fk` FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `comment_reports` ADD CONSTRAINT `comment_reports_reporter_uid_users_id_fk` FOREIGN KEY (`reporter_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `comments` ADD CONSTRAINT `comments_post_id_posts_id_fk` FOREIGN KEY (`post_id`) REFERENCES `posts`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `comments` ADD CONSTRAINT `comments_author_uid_users_id_fk` FOREIGN KEY (`author_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `stories` ADD CONSTRAINT `stories_author_uid_users_id_fk` FOREIGN KEY (`author_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `story_likes` ADD CONSTRAINT `story_likes_story_id_stories_id_fk` FOREIGN KEY (`story_id`) REFERENCES `stories`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `story_likes` ADD CONSTRAINT `story_likes_uid_users_id_fk` FOREIGN KEY (`uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `story_viewers` ADD CONSTRAINT `story_viewers_story_id_stories_id_fk` FOREIGN KEY (`story_id`) REFERENCES `stories`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `story_viewers` ADD CONSTRAINT `story_viewers_uid_users_id_fk` FOREIGN KEY (`uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `message_reactions` ADD CONSTRAINT `message_reactions_message_id_messages_id_fk` FOREIGN KEY (`message_id`) REFERENCES `messages`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `message_reactions` ADD CONSTRAINT `message_reactions_uid_users_id_fk` FOREIGN KEY (`uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `messages` ADD CONSTRAINT `messages_chat_id_chats_id_fk` FOREIGN KEY (`chat_id`) REFERENCES `chats`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `messages` ADD CONSTRAINT `messages_sender_uid_users_id_fk` FOREIGN KEY (`sender_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `event_chat_messages` ADD CONSTRAINT `event_chat_messages_event_id_events_id_fk` FOREIGN KEY (`event_id`) REFERENCES `events`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `event_chat_messages` ADD CONSTRAINT `event_chat_messages_sender_uid_users_id_fk` FOREIGN KEY (`sender_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `event_registrations` ADD CONSTRAINT `event_registrations_event_id_events_id_fk` FOREIGN KEY (`event_id`) REFERENCES `events`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `event_registrations` ADD CONSTRAINT `event_registrations_user_uid_users_id_fk` FOREIGN KEY (`user_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `events` ADD CONSTRAINT `events_author_uid_users_id_fk` FOREIGN KEY (`author_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `poll_votes` ADD CONSTRAINT `poll_votes_poll_id_polls_id_fk` FOREIGN KEY (`poll_id`) REFERENCES `polls`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `poll_votes` ADD CONSTRAINT `poll_votes_uid_users_id_fk` FOREIGN KEY (`uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `polls` ADD CONSTRAINT `polls_created_by_uid_users_id_fk` FOREIGN KEY (`created_by_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `fcm_tokens` ADD CONSTRAINT `fcm_tokens_uid_users_id_fk` FOREIGN KEY (`uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `notifications` ADD CONSTRAINT `notifications_target_uid_users_id_fk` FOREIGN KEY (`target_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `contact_requests` ADD CONSTRAINT `contact_requests_user_uid_users_id_fk` FOREIGN KEY (`user_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE `sticker_packs` ADD CONSTRAINT `sticker_packs_owner_uid_users_id_fk` FOREIGN KEY (`owner_uid`) REFERENCES `users`(`id`) ON DELETE cascade ON UPDATE no action;