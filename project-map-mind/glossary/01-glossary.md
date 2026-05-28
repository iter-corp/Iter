# Glossary

Project-specific terms, models, statuses, and invented names that appear in the code. Entries are alphabetical. Where useful, see-also links point to source files (Firestore docs are referenced by collection name).

---

**Academic level** — One of `Undergraduate` / `Masters` / `PhD` / `Faculty`. Profile personalization field shown during onboarding/edit profile; admin-overridable list lives in `kProfileAcademicLevelOptions`. See `lib/src/services/admin_service.dart`.

**AdminConfig** — Single Firestore doc at `adminConfig/app` holding feature flags (`storiesEnabled`, `repostsEnabled`, `translateEnabled`), `maintenanceMode`, `minAppVersion`, contact email, store URLs, and admin-editable option lists (event types, profile fields, profanity words). Streamed via `adminConfigProvider`. See `lib/src/services/admin_service.dart`.

**AdminEvent** — Event document model. Holds title, subtitle, location, deadline, `eventType`, `country` / `locationCountry`, `funds`, optional `geo.lat/lng`, and `createdByUid`. See `lib/src/services/admin_service.dart`.

**Announcement** — A free-text string set in `AdminConfig.announcement` that shows as an in-app banner; cleared when empty.

**AppFeedback** — Project wrapper around `ScaffoldMessenger` that shows themed snackbars via `showSuccess`, `showInfo`, `showError` (plus `*On` variants that take a captured `ScaffoldMessengerState` for use after navigation pops). See `lib/src/utils/app_feedback.dart`.

**AppGlassCard** — Shared glass-morphism card widget (blurred backdrop + translucent surface + subtle border) used to wrap most content tiles, headers, and tool panels. See `lib/src/features/widgets/app_page_background.dart`.

**AppLanguage** — Enum of supported UI languages: `english` (`en`), `arabic` (`ar`, RTL), `kurdish` (`ckb`, RTL, Sorani / Arabic-script). See `lib/src/providers/locale_provider.dart`.

**AppNotification** — Firestore notification doc at `notifications/{uid}/items/{id}`. Has a `type` (one of `follow`, `like`, `comment`, `comment_like`, `reply`, `qa_answer`, `qa_reply`, `qa_answer_like`, `qa_answer_dislike`, `story_like`, `story_comment`, `story_reply`, `new_event`, `repost`, `role_update`), an `actorUid`, optional `targetId` / `commentId`, `read` flag, optional `status`, and optional system `title`/`subtitle`. See `lib/src/services/notification_service.dart`.

**AppPageBackground** — Shared gradient + ambient-glow background used by every top-level screen and by `flexibleSpace:` on AppBars to make the bar blend with the page. See `lib/src/features/widgets/app_page_background.dart`.

**AppStrings** — Map-backed localization layer (no codegen). English is the source of truth; missing Arabic/Kurdish keys fall back to English. Accessed via `context.t`. See `lib/src/l10n/app_strings.dart`.

**Avatar** — User profile image. Stored on the user doc as `avatarUrl`; denormalized onto each post / comment / story as `authorAvatar` so the feed can render without joining `users/`.

**Backend keys (English)** — Several enum-like strings (e.g. report reasons, role names) are stored in Firestore in English so admin tools stay readable across locales. The UI translates them via helpers like `context.t.reportReasonLabel(englishKey)`. See "Report reasons".

**Blacklist** — Email blacklist used by the auth flow. Adding a user to the blacklist (and cascading their data delete) is handled by `AdminService.deleteUser`. See `lib/src/features/screens/admin/admin_blacklist_screen.dart`.

**Block** — Mutual-mute of another user. Stored under `users/{uid}/blocked/{otherUid}`. Filtered out of `feedProvider` and `qaFeedProvider`. See `lib/src/services/block_service.dart`.

**Bottom nav** — The floating glass pill at the bottom of `MainScreen`. Five tabs in order: `Home`, `Events`, `Translate`, `Messages`, `Profile`. The "Events" icon is `Icons.diversity_3_rounded` and the tab encompasses both Events and Connect (see "Connect"). See `lib/src/features/model/main_screen.dart`.

**ChatMessage** — Direct-message / group-chat message model. Fields cover text, image, video, file, voice (with `voiceTranscript`), sticker, location, reply context, story-reply context, `seenBy`, and `profanityFiltered`. The `enc` envelope field carries an encrypted payload that the client decrypts; the model exposes `encryptedUnreadable` when decryption failed on this device. See `lib/src/services/chat_service.dart`.

**Connect** — The "people / partners" half of the segmented toggle on the Events tab. Localized as `eventsConnect`; the other half is "Events". See `lib/src/features/screens/event_screen.dart` line 420.

**Contact request** — Submission from the "Contact us" screen, often the path users use to request `org_admin` access. Stored in the `contactRequests` collection. See `lib/src/services/contact_request_service.dart`, `lib/src/features/screens/admin/admin_contact_requests_screen.dart`.

**Deep link / FCM tap** — When the OS opens the app via an FCM push notification, `FcmService.events` emits an `FcmMessageEvent(openedApp: true)`. `MyApp._handleFcmEvent` reads `data['type']` / `data['targetId']` and currently routes `type == 'new_event'` to `EventDetailScreen`. See `lib/main.dart` and `lib/src/services/fcm_service.dart`.

**Discuss** — In-app Q&A feature. A Discuss thread is a regular `posts/{id}` document tagged with `postType: 'qa'` and `discussKind: 'question'` or `'discussion'`. Comments on a Discuss post are answers. See "discussKind", "discussTopicId", "sourcePostId" and `lib/src/services/post_service.dart` (`createQaPost`, `createQaPostFromPost`).

**discussKind** — String field on a QA post: `'question'` (asked-only) or `'discussion'` (created by promoting a feed/travel post). Drives the Q&A vs Discussion icon and copy in the feed tile. See `post_model.dart`.

**discussTopicId** — Field on a feed/travel post that was turned into a Discuss topic. Holds the id of the QA post. Lets the post's menu switch to "View in Discuss". See `post_model.dart`.

**EncryptedUnreadable** — Flag on a `ChatMessage` set to `true` when the doc had an `enc` envelope but this device couldn't decrypt it; the chat bubble shows a "🔒 Couldn't decrypt on this device" placeholder.

**Error report** — Document in `errorReports/`. Captured by `ErrorReportService` for uncaught Flutter framework errors, zone errors, and manual `report()` calls. Rate-limited (25/session, 3s gap, signature dedupe). Visible in `AdminErrorReportsScreen`. See `lib/src/services/error_report_service.dart`.

**Event chat** — Group chat attached to an event for registered attendees. Modeled by `EventChatMessage` and `EventChatSummary`. See `lib/src/services/event_chat_service.dart`, `event_chat_screen.dart`, `event_group_settings_screen.dart`.

**Event registration** — A user's RSVP to an event. Stored under `events/{eventId}/registrations/{uid}` plus a mirror on the user. See `lib/src/services/event_registration_service.dart`.

**Event type** — One of `kEventTypes` (`Scholarship`, `Internship`, `Research`, `Conference`, `Summer Program`, `Competition`, `Leadership`, `Youth Summit`, `other`). Admin-editable. Used both for tagging events and for per-user notification filters.

**eventCountries** — Static list of all countries + `Online`, used for event tagging. Always read from `kEventCountries`; the admin dashboard does not edit this list.

**FCM token** — The device's Firebase Cloud Messaging token. Persisted under the user doc after `FcmService.init(uid)`; removed on sign-out. iOS needs an APNS token to exist before `getToken()` works; the service polls for it.

**Feature flag** — One of `storiesEnabled`, `repostsEnabled`, `translateEnabled` on `AdminConfig`. Lets admins kill a feature without a release.

**Feed** — The reverse-chronological public post stream filtered by `following + self`, minus blocked authors. Provider: `feedProvider`. See `lib/src/providers/post_providers.dart`.

**Funding status** — Event tag describing financial support level: one of `kEventFundingStatuses` = `Fully Funded` / `Partially Funded` / `Self Funded`. Stored on the event doc as `funds`.

**`Iter Team`** — String used as the actor name on system notifications about role changes (`'Iter Team made you an admin.'`, `'Iter Team approved you as an event manager.'`). See `AdminService.setRole`.

**Locale** — Currently-active UI language. Reactive: changing `localeProvider` rebuilds `MaterialApp` and re-resolves all `context.t.*` lookups; no restart needed.

**locationCountry** — The country stored on an event doc, lower-cased. Paired with `country` (original casing) for display. The lower-cased copy is the matching key.

**maintenanceMode** — `AdminConfig.maintenanceMode` flag. Admins can flip the app into a read-only / message-only state without a release.

**MessageCache** — On-disk cache (`lib/src/services/message_cache.dart`) for synchronous first-paint of `streamMessages`. Wiped (`clearAll()`) on sign-out so a new user on the same device can't see plaintext previews of the prior user's chats.

**Min app version** — `AdminConfig.minAppVersion`. The `_VersionGate` in `main.dart` blocks the app with an "Update required" screen if `PackageInfo.version < minAppVersion`. Fails open if either string is missing/unparseable.

**navToken** — Counter on the story viewer (`_navToken` in `story_viewer_screen.dart`). Bumped each time the user navigates between stories; in-flight video-ready callbacks check the captured token before mutating state, dropping stale signals from the previous story.

**New event notification** — Pushed/created when an admin publishes a new event, with `type: 'new_event'` and `targetId: eventId`. Tapping it opens `EventDetailScreen`.

**Onboarding** — Multi-step sign-up flow that collects personalization fields (profession, field, academic level, goals). See `lib/src/features/screens/auth/onboarding_screen.dart` and `lib/src/features/widgets/personalization_fields.dart`.

**org_admin** — Limited admin role for users approved through the "organization" contact-us flow. Can post and manage *their own* events (`manageableEventsProvider` filters by `createdByUid`) but not other admin tooling. See `lib/src/providers/admin_providers.dart`.

**Overlay (story)** — A free-text overlay on a story (image/video) — a `StoryTextOverlay`. For image stories the overlay is baked into the uploaded composite *and* stored structurally; for video stories the structured list is the only source of truth (Flutter can't bake into video bytes). See `lib/src/features/widgets/story_text_overlay.dart` and `Story.overlays`.

**Personalization fields** — Profile data captured in onboarding: `profession`, `field` (of study/work), `academicLevel`, `goal`. Each falls back to canonical lists in `lib/src/services/admin_service.dart` if admin-overridden lists are empty.

**Post** — Feed/travel/QA post model. Fields cover author, caption, image/video URLs, like/comment counts, `isPrivate`, optional `postPlaceName/City/Lat/Lng` and `travelDistanceKm` for travel posts, and `discussKind` / `discussTopicId` / `sourcePostId` for the Discuss integration. See `lib/src/features/model/post_model.dart`.

**postType** — String on a post doc. Defaults to a regular feed post; `'qa'` marks Discuss posts which are filtered out of the regular feed.

**Preferred language** — A user's chat translation target language, set per-conversation. See `lib/src/providers/preferred_language_provider.dart`.

**Presence** — Online/last-seen state stored in Firebase Realtime Database under `presence/{uid}` (NOT Firestore). Set on by `PresenceService.setOnline`, set off on lifecycle pause/background and on sign-out; an `onDisconnect` handler auto-clears it if the socket drops. See `lib/src/services/presence_service.dart`.

**Profanity** — Two-tier moderation: posts and Discuss questions are *blocked* on submit if any word in `kProfanityWordsEn` (or the admin-overridden list) matches; chat messages and comments are not blocked but the offending parts are hidden from everyone *except the sender*, who sees them with a "Visible only to you" badge ("sender-only profanity"). See `lib/src/services/profanity_filter_service.dart`.

**Profile visitor** — Records when another user opens your profile. Stored under `users/{uid}/profileVisitors/`. See `lib/src/services/profile_visitor_service.dart`, `profile_visitors_screen.dart`.

**QA / Q&A** — Synonym for "Discuss". `qaFeedProvider`, `qa_thread_screen.dart`, `userQaAskedProvider`, `userQaAnsweredProvider`.

**Reaction** — Emoji reaction on a chat message (the "❤️🔥👏👍😂😮😢" bar above a long-pressed bubble). See `lib/src/services/reaction_service.dart` and `message_reactions_bar.dart`.

**Repost** — Sharing someone else's post to your own profile. Stored under `posts/{id}/reposts/{uid}` and `users/{uid}/reposts/{postId}`. Disable-able via the `repostsEnabled` feature flag. See `lib/src/services/post_service.dart`.

**Report** — User-submitted moderation flag. Variants: `PostReport`, `UserProfileReport`, and Discuss-report (same shape as `PostReport`). Stored in `postReports`, `discussReports`, `userProfileReports`. The `reason` is an English key (see "Report reasons").

**Report reasons** — Stored in Firestore as English keys (`'Spam or scam'`, `'Impersonation'`, `'Harassment or bullying'`, `'Hate speech'`, `'Violence or threats'`, `'Nudity or sexual content'`, `'Misinformation'`, `'Something else'`). The UI translates them via `context.t.reportReasonLabel(englishReason)`. See `lib/src/l10n/app_strings.dart` line 1907.

**Role** — One of `'user'` (default), `'admin'` (full admin), `'org_admin'` (limited, event-only). Stored on the user doc as `role`. Read via `isAdminProvider`, `isOrgAdminProvider`.

**Save** — Bookmark a post. Stored under `users/{uid}/saved/{postId}`. See `post_service.dart` `toggleSave`.

**Saved translation** — A chat-message translation the user explicitly saved. Stored under `users/{uid}/savedTranslations/`. See `saved_translations_screen.dart`.

**Sender-only profanity** — See "Profanity". Implemented via `senderOnlyText` on the chat / comment doc; the chat-message factory prefers it when present. The badge string key is `visible_only_to_you`.

**sourcePostId** — Set on a Discuss (QA) post that was created from an existing feed/travel post. Holds the original post's id so the Discuss thread can embed it.

**Splash → version-gate → router** — The startup sequence: `_VersionGate` decides whether to overlay an "Update required" screen, then `routerProvider` redirects based on auth state to `/splash`, `/login`, `/onboarding`, or `/home`.

**Sticker pack** — Bundled or user-uploaded sticker set. Bundled assets use a `stickerUrl` starting with `asset:`; custom stickers store a Firebase Storage URL. See `lib/src/services/sticker_service.dart`, `sticker_data.dart`.

**Story** — Ephemeral post (24h expiry) at `stories/{id}`. Three kinds: **image** (just `imageUrl`), **video** (has `videoUrl`, optionally trimmed via `videoTrimStartMs`/`EndMs`), and **text-only** (has `textContent` + `backgroundColor`). Can also be a *shared* story that embeds an existing post via `sharedPostId`. See `lib/src/services/story_service.dart`.

**StoryComment** — Comment on a story. Lives under `stories/{id}/comments`. Supports nested replies via `parentCommentId` and `replyToUsername`. See `lib/src/features/model/story_comment_model.dart`.

**StoryViewer** — Record of a single user who viewed a story (the "seen-by" list). Lives under `stories/{id}/viewers/{uid}`.

**Suspended** — Flag on the user doc set by `AdminService.suspendUser`. Suspended users are signed out and rejected by Firestore rules.

**Translate / Translate tab** — Third bottom-nav tab. Wraps Google Translate via a Cloud Function. Disabled when `translateEnabled = false`. See `lib/src/features/screens/translate_screen.dart`, `lib/src/services/translate_service.dart`.

**Travel** — Location-tagged feed of posts. A post becomes a "travel post" when it has `postPlaceName` / `postPlaceCity` / `postLat` / `postLng`. The travel feed is served by a Cloud Function (`Post.fromTravelMap` decodes the response) and ranks by distance. See `travelFeedProvider` and `post_model.dart`.

**Trim window** — Optional `videoTrimStartMs` / `videoTrimEndMs` on a video story. The uploaded file is unchanged (no re-encode) — the viewer clamps playback to the window. Either bound may be null = "use natural start/end". See `story_service.dart` and `story_viewer_screen.dart` line 2450 (defensive fallback when malformed).

**Typing indicator** — Live "X is typing…" state stored in Firebase RTDB at `typing/{chatId}/{uid}`. Auto-cleared by an `onDisconnect` remove if the user drops. See `lib/src/services/typing_service.dart`.

**Unblock** — Reverse of "Block".

**Update required** — See "Min app version" / `_VersionGate`.

**user (role)** — Default role on every user doc. The only role that cannot access `/admin`.

**Username taken** — Auth flow check during onboarding. Key `auth_username_taken` / `context.t.authUsernameTaken`.

**Version gate** — `_VersionGate` in `lib/main.dart`. Overlays the running app with an "Update required" screen when `current < AdminConfig.minAppVersion`.

**Voice transcript** — Speech-to-text captured on the sender's device while recording a voice message, stored on the message doc as `voiceTranscript`. Lets the recipient read or translate the audio without a server-side transcription job.

---

## Related files

- `lib/src/features/model/post_model.dart`, `message_model.dart`, `story_comment_model.dart`, `main_screen.dart`
- `lib/src/services/admin_service.dart`, `notification_service.dart`, `story_service.dart`, `chat_service.dart`, `post_service.dart`, `presence_service.dart`, `typing_service.dart`, `fcm_service.dart`, `error_report_service.dart`, `profanity_filter_service.dart`
- `lib/src/providers/admin_providers.dart`, `auth_providers.dart`, `post_providers.dart`, `locale_provider.dart`
- `lib/src/l10n/app_strings.dart`, `ckb_material_localizations.dart`
- `lib/src/features/widgets/app_page_background.dart`
- `lib/src/features/screens/event_screen.dart`, `story_viewer_screen.dart`, `home_screen.dart`
- `lib/main.dart`, `lib/firebase_options.dart`
