# State Providers (Riverpod)

All app state is managed through [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod). Providers live in [`lib/src/providers/`](../../lib/src/providers/) and are organized by domain. Every provider follows the same pattern: a `*ServiceProvider` exposes the singleton service, and consumer providers wrap the service's streams/futures with auth-gating and side-effects.

`ProviderScope` is mounted in [`main.dart`](../../lib/main.dart) with one override: `sharedPreferencesProvider.overrideWithValue(prefs)` (the pre-loaded `SharedPreferences` instance).

## Auth & user identity

File: [`lib/src/providers/auth_providers.dart`](../../lib/src/providers/auth_providers.dart)

| Provider | Type | Provides | Watches | Consumers |
|---|---|---|---|---|
| `authServiceProvider` | `Provider<AuthService>` | Singleton `AuthService`. | — | Everything auth-related. |
| `userServiceProvider` | `Provider<UserService>` | Singleton `UserService`. | — | Edit profile, settings, follow flows. |
| `authStateProvider` | `StreamProvider<User?>` | Firebase `User?` after token has been fetched. `asyncMap`s the raw stream through `user.getIdToken()` + a 50ms yield so Firestore streams don't open with a stale token. | `authService.authStateChanges`. | Router redirect, every gated provider, main app for FCM init / presence / cache clear. |
| `currentUserDocProvider` | `StreamProvider<Map<String, dynamic>?>` | The signed-in user's `users/{uid}` doc, retried up to 3× with backoff via `_retryStream` to absorb transient permission-denied right after sign-in. | `authStateProvider.select((v) => v.value?.uid)` — only rebuilds when UID changes (token refresh re-emissions are filtered out). | Router redirect, profile screen, settings screens, `isAdminProvider`, `isOrgAdminProvider`. |
| `userByUidProvider` | `StreamProvider.autoDispose.family<Map<String, dynamic>?, String>` | Live user doc for any UID. Used to render an author's current avatar/username on legacy content. | `userServiceProvider`. | Comments, posts, story headers, user tiles. |

## Admin & app config

File: [`lib/src/providers/admin_providers.dart`](../../lib/src/providers/admin_providers.dart)

| Provider | Type | Provides | Notes |
|---|---|---|---|
| `adminServiceProvider` | `Provider<AdminService>` | Singleton. | |
| `adminConfigProvider` | `StreamProvider<AdminConfig>` | App-wide kill switches (`storiesEnabled`, `repostsEnabled`, `translateEnabled`, `maintenanceMode`, `minAppVersion`, `contactEmail`, `iosAppStoreUrl`, `androidPlayStoreUrl`, `eventTypes`, `profileXxxOptions`, `profanityWordsEn`). | Drives `_VersionGate`, feature flags across the app. Gated on `authStateProvider`. |
| `isAdminProvider` | `Provider<bool>` | `userDoc['role'] == 'admin'`. | Gates admin UI. |
| `isOrgAdminProvider` | `Provider<bool>` | `userDoc['role'] == 'org_admin'`. | Gates the limited event-posting role. |
| `adminUsersProvider` | `StreamProvider.family<List<Map>, String>` | Users matching a search query (admin manage-users). | |
| `adminPostsProvider` | `StreamProvider<List<Map>>` | Regular posts (excludes `postType == 'qa'`). | |
| `adminDiscussPostsProvider` | `StreamProvider<List<Map>>` | Discuss/Q&A posts only. | |
| `postReportsProvider` | `StreamProvider<List<PostReport>>` | Pending post reports. | Admin-gated. |
| `discussReportsProvider` | `StreamProvider<List<PostReport>>` | Pending discuss-post reports. | Admin-gated. |
| `userProfileReportsProvider` | `StreamProvider<List<UserProfileReport>>` | Pending user-profile reports. | Admin-gated. |
| `errorReportAdminProvider` | `Provider<ErrorReportAdmin>` | Reader for `errorReports` collection. | |
| `errorReportsProvider` | `StreamProvider<List<ErrorReport>>` | All client-captured error reports, newest first, limit 200. | Admin-gated. |
| `adminEventsProvider` | `StreamProvider<List<AdminEvent>>` | EVERY event in the system. Public-facing events tab reads this — NOT role-scoped. | |
| `manageableEventsProvider` | `StreamProvider<List<AdminEvent>>` | Events the user is allowed to manage. Full admins see all; `org_admin` users see only events they created (mirrors Firestore rules). | |
| `blacklistProvider` | `StreamProvider<List<Map>>` | Deleted-user email blacklist. | |

## Admin report-seen tracking

File: [`lib/src/providers/admin_report_notifications_provider.dart`](../../lib/src/providers/admin_report_notifications_provider.dart)

Tracks last-time each admin opened a given report category so the dashboard can show "new" dots.

| Provider | Type | Provides |
|---|---|---|
| `adminReportSeenProvider` | `StateNotifierProvider<AdminReportSeenNotifier, AdminReportSeenState>` | Persisted timestamps (SharedPreferences keys `admin_post_reports_seen_at_ms`, `admin_discuss_reports_seen_at_ms`, `admin_profile_reports_seen_at_ms`, `admin_error_reports_seen_at_ms`). Exposes `markPostReportsSeen()`, `markDiscussReportsSeen()`, `markProfileReportsSeen()`, `markErrorReportsSeen()`. |
| `hasNewPostReportsProvider` | `Provider<bool>` | True if there's an unresolved post report newer than the last seen-at. |
| `hasNewDiscussReportsProvider` | `Provider<bool>` | Same for discuss reports. |
| `hasNewProfileReportsProvider` | `Provider<bool>` | Same for user-profile reports. |
| `hasNewErrorReportsProvider` | `Provider<bool>` | Same for error reports. |
| `hasAnyNewReportsProvider` | `Provider<bool>` | OR of the four above — drives the global "new reports" indicator on the admin dashboard tile. |

## Theme & locale

| Provider | File | Type | Provides |
|---|---|---|---|
| `sharedPreferencesProvider` | [`theme_provider.dart`](../../lib/src/providers/theme_provider.dart) | `Provider<SharedPreferences>` (overridden in `runApp`) | The pre-loaded prefs instance, readable synchronously by all dependents. |
| `themeModeProvider` | [`theme_provider.dart`](../../lib/src/providers/theme_provider.dart) | `StateNotifierProvider<ThemeModeNotifier, ThemeMode>` | Light/dark mode, persisted under `isDarkMode`. Default: dark. Methods: `toggle()`, `setMode(ThemeMode)`. |
| `localeProvider` | [`locale_provider.dart`](../../lib/src/providers/locale_provider.dart) | `StateNotifierProvider<LocaleNotifier, AppLanguage>` | Active UI language (`english`/`arabic`/`kurdish`). Persisted under `app_ui_language`. On first launch falls back to device language when supported, otherwise English. Method: `setLanguage(AppLanguage)`. |
| `preferredLanguageProvider` | [`preferred_language_provider.dart`](../../lib/src/providers/preferred_language_provider.dart) | `StateNotifierProvider<PreferredLanguageNotifier, String>` | BCP-47 code for auto-translating INCOMING content (separate from `localeProvider`). Default `'en'`. Persisted under `app_preferred_lang`. Method: `set(String code)`. |

## Posts & feed

File: [`lib/src/providers/post_providers.dart`](../../lib/src/providers/post_providers.dart)

| Provider | Type | Provides |
|---|---|---|
| `postServiceProvider` | `Provider<PostService>` | Singleton. |
| `singlePostProvider` | `FutureProvider.family<Post?, String>` | One post by id (used to embed a post inside a Discuss thread). |
| `feedProvider` | `StreamProvider<List<Post>>` | Main feed. Uses `Rx.combineLatest3(streamFeed, getFollowing, getBlockedUsers)` and filters private posts to `following ∪ {self}`, then removes blocked authors. Errors are absorbed via `onErrorReturn([])` so a broken stream doesn't blank the feed. |
| `qaFeedProvider` | `StreamProvider<List<Post>>` | Same as `feedProvider` but for Q&A/Discuss posts. |
| `userPostsProvider` | `StreamProvider.family<List<Post>, String>` | A user's regular posts. |
| `userQaAskedProvider` | `StreamProvider.family<List<Post>, String>` | A user's asked Q&A questions. |
| `userQaAnsweredProvider` | `StreamProvider.family<List<Post>, String>` | A user's answered Q&A questions. |
| `travelFeedProvider` | `FutureProvider.family<List<Post>, TravelFeedQuery>` | Travel-mode posts (filtered by place name + GPS proximity). |
| `isLikedProvider` | `StreamProvider.family<bool, String>` (postId) | Whether the signed-in user has liked the post. |
| `isRepostedProvider` | `StreamProvider.family<bool, String>` (postId) | Whether the user has reposted. |
| `repostsCountProvider` | `StreamProvider.family<int, String>` | Live repost count. |
| `repostUserIdsProvider` | `StreamProvider.family<List<String>, String>` | UIDs of repost authors. |
| `userRepostsProvider` | `StreamProvider.family<List<Post>, String>` | Reposts on a user's profile. |
| `isSavedProvider` | `StreamProvider.family<bool, String>` | Whether the user has saved the post. |
| `userSavedProvider` | `StreamProvider.family<List<Post>, String>` | A user's saved-posts tab. |

Consumers: `home_screen.dart`, `profile_screen.dart`, `user_screen.dart`, `post_card.dart`, `main_screen.dart` (to invalidate feed on Home tap).

## Comments / QA

File: [`lib/src/providers/comment_providers.dart`](../../lib/src/providers/comment_providers.dart). Also defines a local `_retryStream<T>` (same shape as the one in `auth_providers.dart`) to ride out post-login permission-denied.

| Provider | Type | Provides |
|---|---|---|
| `commentServiceProvider` | `Provider<CommentService>` | Singleton. |
| `commentsProvider` | `StreamProvider.family<List<Comment>, String>` (postId) | Merged public + per-user-private comments. Auth-gated. |
| `commentsCountProvider` | `StreamProvider.family<int, String>` (postId) | Live public-comment count — counts the subcollection directly so it never drifts negative like the cached `post.commentsCount`. |
| `userAnswerReactionProvider` | `StreamProvider.family<String?, UserAnswerReactionArgs>` | The current user's heart/broken reaction on a specific answer. Args = `(postId, commentId, uid)`. |

## Follow

File: [`lib/src/providers/follow_providers.dart`](../../lib/src/providers/follow_providers.dart)

| Provider | Type | Provides |
|---|---|---|
| `followServiceProvider` | `Provider<FollowService>` | Singleton. |
| `isFollowingProvider` | `StreamProvider.family<bool, String>` (targetUid) | True if active (non-pending) follow. |
| `hasRequestedFollowProvider` | `StreamProvider.family<bool, String>` | True if user has a pending request out to target. |
| `followersProvider` | `StreamProvider.family<List<String>, String>` (uid) | UIDs following [uid] (active only). |
| `followingProvider` | `StreamProvider.family<List<String>, String>` (uid) | UIDs that [uid] follows (active only). |
| `followRequestsProvider` | `StreamProvider.family<List<String>, String>` (uid) | Pending follow request actors. Drives the notification bell badge. |

## Block

File: [`lib/src/providers/block_providers.dart`](../../lib/src/providers/block_providers.dart)

| Provider | Type | Provides |
|---|---|---|
| `blockServiceProvider` | `Provider<BlockService>` | Singleton. |
| `isBlockedProvider` | `StreamProvider.family<bool, String>` (targetUid) | True if current user blocked target. Falls back to `authServiceProvider.currentUser` when `authStateProvider` is mid-init. |
| `isBlockedByProvider` | `StreamProvider.family<bool, String>` | True if target blocked current user. |
| `blockedUsersProvider` | `StreamProvider<List<String>>` | UIDs the current user has blocked. Consumed by `feedProvider`/`qaFeedProvider` to filter posts. |

## Chat / presence / typing

File: [`lib/src/providers/chat_providers.dart`](../../lib/src/providers/chat_providers.dart)

| Provider | Type | Provides |
|---|---|---|
| `chatServiceProvider` | `Provider<ChatService>` | Singleton. |
| `presenceServiceProvider` | `Provider<PresenceService>` | Singleton (RTDB). |
| `typingServiceProvider` | `Provider<TypingService>` | Singleton (RTDB). |
| `inboxProvider` | `StreamProvider<List<ChatConversation>>` | All conversations for the current user (includes requests). Consumed by `MainScreen` for the message-tab badge. |
| `requestsProvider` | `StreamProvider<List<ChatConversation>>` | Only `isRequest` chats (filters out mutual-friends from the request tab). |
| `acceptedInboxProvider` | `StreamProvider<List<ChatConversation>>` | Non-request chats (includes mutual-friend chats even if their `acceptedBy` is incomplete). |
| `messagesProvider` | `StreamProvider.autoDispose.family<List<ChatMessage>, String>` (chatId) | Live messages for one chat. |
| `chatDocProvider` | `StreamProvider.autoDispose.family<Map<String, dynamic>?, String>` (chatId) | Raw `chats/{chatId}` doc — chat screen reads this to detect group vs direct. |
| `typingWatchProvider` | `StreamProvider.family<bool, String>` | Key format `"chatId|otherUid"`. |
| `presenceWatchProvider` | `StreamProvider.family<PresenceData, String>` (uid) | Live presence (online + lastSeen). |

## Polls

File: [`lib/src/providers/poll_providers.dart`](../../lib/src/providers/poll_providers.dart)

| Provider | Type | Provides |
|---|---|---|
| `pollServiceProvider` | `Provider<PollService>` | Singleton. |
| `pollsProvider` | `StreamProvider.family.autoDispose<List<Poll>, String>` | Polls at parent path (`"chats/{id}"` or `"eventChats/{id}"`). |
| `pollVotesProvider` | `StreamProvider.family.autoDispose<List<PollVote>, String>` | Key `"{parentPath}::{pollId}"`. |
| `myVoteProvider` | `StreamProvider.family.autoDispose<PollVote?, String>` | Same key shape — the signed-in user's vote. |

## Reactions

File: [`lib/src/providers/reaction_providers.dart`](../../lib/src/providers/reaction_providers.dart)

| Provider | Type | Provides |
|---|---|---|
| `reactionServiceProvider` | `Provider<ReactionService>` | Singleton. |
| `myReactionProvider` | `StreamProvider.family<String?, String>` | Key `"parentPath::messageId"`. Current user's emoji reaction. |
| `reactionCountsProvider` | `StreamProvider.family<Map<String, int>, String>` | Same key shape. Aggregated emoji counts. |

## Contact requests (Contact-us)

File: [`lib/src/providers/contact_request_providers.dart`](../../lib/src/providers/contact_request_providers.dart)

| Provider | Type | Provides |
|---|---|---|
| `contactRequestServiceProvider` | `Provider<ContactRequestService>` | Singleton. |
| `myContactRequestsProvider` | `StreamProvider<List<ContactRequest>>` | The current user's own threads. |
| `allContactRequestsProvider` | `StreamProvider<List<ContactRequest>>` | Every thread (admin-only; Firestore rules reject non-admins). |
| `contactRequestMessagesProvider` | `StreamProvider.autoDispose.family<List<ContactRequestMessage>, String>` | Messages inside one thread. |
| `hasUnreadContactRequestsProvider` | `Provider<bool>` | True if any thread has `unreadByAdmin`. Drives admin dashboard dot. |
| `hasUnreadAdminReplyProvider` | `Provider<bool>` | True if any of the user's own threads has `unreadByUser`. Drives the user-side Settings dot. |

## Event registrations & event chats

File: [`lib/src/providers/event_registration_providers.dart`](../../lib/src/providers/event_registration_providers.dart)

| Provider | Type | Provides |
|---|---|---|
| `eventRegistrationServiceProvider` | `Provider<EventRegistrationService>` | Singleton. |
| `pendingRegistrationsProvider` | `StreamProvider.autoDispose<List<EventRegistration>>` | All pending registrations (admin). |
| `myRegistrationProvider` | `StreamProvider.autoDispose.family<EventRegistration?, String>` | The current user's registration for one event. |

File: [`lib/src/providers/event_chat_providers.dart`](../../lib/src/providers/event_chat_providers.dart)

| Provider | Type | Provides |
|---|---|---|
| `eventChatServiceProvider` | `Provider<EventChatService>` | Singleton. |
| `myEventChatsProvider` | `StreamProvider.autoDispose<List<EventChatSummary>>` | Every event chat the current user is a member of (or admin of). |
| `eventChatMessagesProvider` | `StreamProvider.family<List<EventChatMessage>, String>` | Messages for one event chat. |
| `eventChatAdminProvider` | `StreamProvider.family<String?, String>` | Admin UID for the event chat (drives compose visibility). |
| `eventChatMembersProvider` | `StreamProvider.family<List<Map>, String>` | Member list for one event chat. |
| `sharedEventProvider` | `FutureProvider.autoDispose.family<Map<String, String>?, String>` | Key `"uidA|uidB"`. Most recent event chat both users are in (admin or member). Returns `{eventId, eventTitle}` or null. |

## Notifications

File: [`lib/src/providers/notification_providers.dart`](../../lib/src/providers/notification_providers.dart)

| Provider | Type | Provides |
|---|---|---|
| `notificationServiceProvider` | `Provider<NotificationService>` | Singleton. |
| `eventNotifPrefsProvider` | `StreamProvider<EventNotifPrefs>` | The user's new-event notification filter (mode + types + countries). |
| `notificationsProvider` | `StreamProvider<List<AppNotification>>` | Live last-50 notifications. |
| `unreadCountProvider` | `Provider<int>` | `unread persisted notifications + pending follow requests that aren't already represented as `follow_request` docs`. Drives the bell badge. |

## Stories

File: [`lib/src/providers/story_providers.dart`](../../lib/src/providers/story_providers.dart)

| Provider | Type | Provides |
|---|---|---|
| `storyServiceProvider` | `Provider<StoryService>` | Singleton. |
| `activeStoriesProvider` | `StreamProvider<List<Story>>` | Stories where `expiresAt > now`. |
| `locallyViewedStoryIdsProvider` | `StateProvider<Set<String>>` | Session-only mirror of viewed story IDs. Lets the home rail dim a ring immediately without round-tripping Firestore. |
| `storyViewersCountProvider` | `StreamProvider.family<int, String>` (storyId) | Live viewer count for one story. |

Also see [`own_story_seen_service.dart`](../../lib/src/services/own_story_seen_service.dart):

| Provider | Type | Provides |
|---|---|---|
| `ownStorySeenServiceProvider` | `Provider<OwnStorySeenService>` | Local SharedPreferences mirror — has the author opened this own-story? |
| `ownStorySeenProvider` | `StateNotifierProvider<OwnStorySeenNotifier, OwnStorySeenState>` | In-memory snapshot of seen-by-author flags + last-seen viewer counts (lets the home ring re-highlight when a new viewer arrives). |
| `ownStoriesAllSeenProvider` | `Provider.family<bool, List<OwnStoryViewerSnapshot>>` | Derived — false if any own-story is unseen OR has gained new viewers since the author's last visit. |

## Profile visitors

File: [`lib/src/providers/profile_visitor_providers.dart`](../../lib/src/providers/profile_visitor_providers.dart)

| Provider | Type | Provides |
|---|---|---|
| `profileVisitorServiceProvider` | `Provider<ProfileVisitorService>` | Singleton. |
| `myProfileVisitorsProvider` | `StreamProvider<List<ProfileVisitorEntry>>` | Live list of who visited the signed-in user's profile, newest first. |
| `myProfileVisitorCountProvider` | `StreamProvider<int>` | Count badge for settings "Profile visitors" entry. |

## Stickers

Defined in the service file itself: [`lib/src/services/sticker_service.dart`](../../lib/src/services/sticker_service.dart)

| Provider | Type | Provides |
|---|---|---|
| `stickerServiceProvider` | `Provider<StickerService>` | Singleton. |
| `customStickerPacksProvider` | `StreamProvider.family<List<CustomStickerPack>, String>` (uid) | User's custom sticker packs from Firestore. |

## City picker (shared world-city source)

Defined in the service file: [`lib/src/services/city_service.dart`](../../lib/src/services/city_service.dart)

| Provider | Type | Provides |
|---|---|---|
| `worldCitiesProvider` | `AsyncNotifierProvider<WorldCitiesNotifier, List<CityOption>>` | One-time lazy load of the ~40k-city `country_state_city` dataset, deduped + sorted. Cached app-wide. Used by Create Post, Onboarding, Connect/People filter, Events filter, Travel search. |

## Patterns & invariants

- **Token-warmup pattern**: `authStateProvider` calls `getIdToken()` + a 50ms yield before emitting. This prevents the firehose of "transient permission-denied" errors that hit Firestore streams in the narrow window after `signInWithCredential` returns.
- **`_retryStream` pattern**: Used in `auth_providers.dart` and `comment_providers.dart` to retry 3 times with 600ms × n backoff for streams that frequently hit post-login permission-denied.
- **UID-only selection**: Most consumer providers use `authStateProvider.select((a) => a.value?.uid)` so token refreshes don't restart Firestore listeners.
- **Empty-stream gating**: Most providers `return const Stream.empty();` when no user — avoids opening unauthenticated Firestore listeners.

## Related files

- [`lib/main.dart`](../../lib/main.dart) — `ProviderScope` mount; `ref.listen<AsyncValue<User?>>(authStateProvider, ...)` reacts to login/logout for FCM, presence, message cache.
- All files in [`lib/src/providers/`](../../lib/src/providers/).
- Services they wrap: [`lib/src/services/`](../../lib/src/services/) (documented in `03-services.md`).
