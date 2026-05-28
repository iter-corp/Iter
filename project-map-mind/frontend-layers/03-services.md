# Services

All Firebase, Supabase, and 3rd-party I/O is encapsulated in service classes under [`lib/src/services/`](../../lib/src/services/). They contain ZERO Riverpod references and ZERO `BuildContext` — they're plain singletons (constructed once each by their `*ServiceProvider`). Providers wrap them.

Common patterns:

- Most services hold a `FirebaseFirestore _db = FirebaseFirestore.instance` field, sometimes also `FirebaseAuth.instance` and `NotificationService`.
- Streams of model objects use `*.fromDoc(DocumentSnapshot)` factory constructors.
- Writes that need notifications fan them out best-effort via `NotificationService.upsertNotification` (deterministic ID = idempotent).
- Cascading deletes batch in groups of 400/450 to stay under Firestore's 500-write batch cap.

## Auth domain

### [`auth_service.dart`](../../lib/src/services/auth_service.dart) — `AuthService`

Email/Google/Apple sign-in plus account-doc bootstrap. Stamps `justSignedUp` so the router can route to onboarding for the current session, but the durable check is whether `users/{uid}.username == null`.

| Method | Purpose |
|---|---|
| `User? get currentUser` | Convenience around `FirebaseAuth.instance.currentUser`. |
| `Stream<User?> get authStateChanges` | Raw `FirebaseAuth.authStateChanges()`. |
| `bool get requiresEmailVerification` | True if the user has an email and `!emailVerified`. |
| `Future<void> sendEmailVerification()` | Reloads then sends a verification email if still unverified. |
| `Future<bool> reloadAndCheckEmailVerified()` | Reload + return `emailVerified`. |
| `Future<void> discardPendingSignup()` | Hard-removes a half-completed sign-up: deletes the user doc, deletes the Auth user. Used when the user backs out of the OTP screen. |
| `Future<User?> signUp({email, password})` | Creates Auth user, writes a default `users/{uid}` doc with `username: null` + `appIntroSeen: false`, sends verification email. Sets `justSignedUp = true`. |
| `Future<User?> signIn({email, password})` | Email/password sign-in. Calls `_ensureUserDoc` to backfill any missing `email`/`avatarUrl` fields. |
| `Future<User?> signInWithGoogle({intent: GoogleAuthIntent.login\|signup})` | Google flow. When `intent == login` and the credential is new, deletes the just-created Auth user and throws `GoogleAuthFlowException`. When new, writes a default user doc. |
| `Future<User?> signInWithApple()` | Sign-in-with-Apple flow with nonce; writes a default doc on new. |
| `Future<void> signOut()` | Signs out of Google + FirebaseAuth. Clears `justSignedUp`. |
| `Future<void> resetPassword(String email)` | `_auth.sendPasswordResetEmail`. |

Firestore: `users/{uid}` reads/writes. Throws `GoogleAuthFlowException` and `AccountDeletedException`.

### [`user_service.dart`](../../lib/src/services/user_service.dart) — `UserService`

Generic user-doc operations + event-notif prefs + report-profile + username uniqueness checks.

| Method | Purpose |
|---|---|
| `Future<Map<String, dynamic>?> getUser(String uid)` | One-shot doc fetch. |
| `Stream<Map<String, dynamic>?> streamUser(String uid)` | Live user doc. |
| `Future<void> updateUser(String uid, Map data)` | `set(merge: true)`. |
| `Stream<EventNotifPrefs> streamEventNotifPrefs(String uid)` | The user's `eventNotifPrefs` substruct (mode + types + countries). |
| `Future<void> setEventNotifPrefs(String uid, EventNotifPrefs prefs)` | Persists same. |
| `Future<void> reportUserProfile({targetUid, targetUsername, targetAvatar, reason, details})` | Writes a `userReports/{targetUid}_{reporterUid}` doc; throws if the user already reported this profile. |
| `String normalizeUsername(String)` | `trim().toLowerCase()`. |
| `Future<bool> isUsernameTaken(String, {excludeUid})` | Three-step check: `usernameLower`, then `username` exact-lowercase, then legacy O(n) scan for older docs. |

Also exports `EventNotifPrefs` model + `EventNotifMode { all, off }`.

## Admin domain

### [`admin_service.dart`](../../lib/src/services/admin_service.dart) — `AdminService`

Admin-only operations: config CRUD, user moderation, post moderation, blacklist, events CRUD, report moderation. Also defines models `AdminConfig`, `AdminEvent`, `PostReport`, `UserProfileReport`, and a long list of canonical constants (`kEventTypes`, `kEventCountries`, `kProfileProfessionOptions`, `kProfileFieldOptions`, `kProfileAcademicLevelOptions`, `kProfileGoalOptions`, `kProfanityWordsEn`, `kEventFundingStatuses`).

| Method | Purpose |
|---|---|
| `Stream<AdminConfig> streamConfig()` | `adminConfig/app` doc → typed model. |
| `Future<void> saveConfig(AdminConfig cfg)` | Persists same with merge. |
| `Stream<List<Map>> streamUsers({query})` | All users, filtered by name/email substring. |
| `Future<void> suspendUser(String uid, bool)` | Sets `suspended` flag. |
| `Future<void> setRole(String uid, String role)` | Updates role + writes a system notification ("Admin access granted", "Event manager access granted", etc.). |
| `Future<void> deleteUser(String uid)` | **Cascade-delete client-side** (Spark plan). Wipes posts + likes/comments/reposts subcols, stories + viewers, chats + messages, followers/following/reposts/saved subcols, collection-group followers/following of others, notifications, eventRegistrations. Finally deletes the user doc and adds the email to the `blacklist`. The Auth record can NOT be deleted from the client. |
| `Future<void> selfDeleteCurrentUser(String uid)` | Best-effort user self-delete: blacklist email, wipe what rules allow, then rename Auth email to `deleted+{uid}@coil.invalid` (RFC 2606) so the real email is freed, then attempt `user.delete()`. |
| `Stream<List<Map>> streamBlacklist()` | Blacklist newest first. |
| `Future<void> removeFromBlacklist(String email)` | |
| `Stream<List<Map>> streamAllPosts({limit})` | Newest first. |
| `Stream<List<Map>> streamRegularPosts({limit})` | Excludes `postType == 'qa'`. Over-fetches 4× to compensate. |
| `Stream<List<Map>> streamDiscussPosts({limit})` | `postType == 'qa'` only. |
| `Future<void> deletePost(String postId)` | Delegates to `PostService.deletePostAsAdmin`. |
| `Stream<List<PostReport>> streamPostReports({limit})` | Newest first. |
| `Future<void> setPostReportResolved(id, bool)` | |
| `Future<void> deletePostReport(String id)` | |
| `Stream<List<PostReport>> streamDiscussReports({limit})` | |
| `Future<void> setDiscussReportResolved(id, bool)` | |
| `Future<void> deleteDiscussReport(String id)` | |
| `Stream<List<UserProfileReport>> streamUserProfileReports({limit})` | |
| `Future<void> setUserProfileReportResolved(id, bool)` | |
| `Future<void> deleteUserProfileReport(String id)` | |
| `Stream<List<AdminEvent>> streamEvents()` | Newest first. |
| `Stream<List<AdminEvent>> streamEventsCreatedBy(uid)` | For `org_admin` filtering. |
| `Future<String> createEvent({...})` | Writes the event then runs `_fanOutNewEventNotifications` from the admin's device (Spark-plan stand-in for an `onEventCreate` Cloud Function). Uses deterministic notification doc IDs `new_event_{eventId}` for idempotency. |
| `Future<void> updateEvent(id, data)` | Keeps `locationCity` + `locationCountry` lowercase keys in sync when `location`/`country` change. Coerces `deadline` from `DateTime` → `Timestamp`. |
| `Future<void> deleteEvent(id)` | Removes all `new_event_{id}` notifs across users, deletes event chat's messages/members, then the event doc. |

Firestore touchpoints: `adminConfig/app`, `users/`, `posts/`, `stories/`, `chats/`, `notifications/`, `eventRegistrations/`, `events/`, `eventChats/`, `postReports/`, `discussReports/`, `userReports/`, `blacklist/`.

### [`error_report_service.dart`](../../lib/src/services/error_report_service.dart) — `ErrorReportService` (+ `ErrorReportNavigatorObserver`, `ErrorReportAdmin`)

**Boots the global error handler.** See `07-error-reporting.md` for the full picture.

- Singleton: `ErrorReportService.instance`.
- `install()` — installs `FlutterError.onError` (chained onto any existing handler) and `PlatformDispatcher.instance.onError`. Must be called AFTER `Firebase.initializeApp()`.
- `runGuarded(body)` — runs `body` inside `runZonedGuarded`. Used in `main()` so the binding init + `runApp` happen in the same zone. Captures uncaught async errors.
- `report(error, stack, {context, kind, screen})` — manual logging hook. Rate-limited: max 25 per session, min 3s gap, 2-minute dedupe window on `signature = '$kind|${msg.split("\n").first}'`.
- `setCurrentScreen(String?)` — manual screen label. Auto-set by the navigator observer for named routes.
- `ErrorReportNavigatorObserver` — registered in `GoRouter(observers: [...])`. Sets `_currentScreen` to `route.settings.name ?? route.runtimeType.toString()` on push/pop/replace/remove.
- `ErrorReportAdmin.stream({limit})` / `setResolved(id, bool)` / `delete(id)` / `clearResolved()` — admin reader/writer.

Firestore: `errorReports/` (writes), with `{message, stack, kind, context?, screen?, uid, platform, appVersion, resolved, createdAt}`. Stack capped at 6000 chars.

## Posts / feed

### [`post_service.dart`](../../lib/src/services/post_service.dart) — `PostService`

Posts, Q&A posts (postType=qa), travel posts, likes, reposts, saves, post reports. Also defines `PostBlockedException`, `DiscussPostBlockedException`, `TravelPlaceResult`.

| Method | Purpose |
|---|---|
| `Future<String> createPost({caption, imageUrls, videoUrls, isPrivate, postPlaceName, postPlaceCity, postLat, postLng, postLocationExact})` | Runs `ProfanityFilterService.findMatches` over caption + place; throws `PostBlockedException` on a hit. Otherwise writes `posts/`, bumps `users/{uid}.postsCount`. |
| `Future<void> reportPost({postId, postAuthorUid, reason, details})` | Writes `postReports/{postId}_{reporterUid}` (one report per user per post). |
| `Future<void> reportQaPost({postId, ..., reason, details})` | Same shape but to `discussReports/`. |
| `Stream<List<Post>> streamFeed({limit})` | All non-qa posts, newest first. |
| `Future<String> createQaPost({...})` | `postType: 'qa'` post. |
| `Future<String> createQaPostFromPost(...)` | Spawns a discuss thread from an existing post. |
| `Future<Post?> getPostById(String postId)` | One-shot. |
| `Future<Set<String>> qaPostsWithMatchingAnswer(query, ...)` | QA search by answer text. |
| `Future<String?> findDiscussTopicForPost(String postId)` | Look up if a post already has an existing discuss thread. |
| `Stream<List<Post>> streamQaFeed({limit})` | Q&A feed. |
| `Future<List<Post>> getTravelPosts({placeQuery, currentLat, currentLng, limit})` | Travel mode (place search + proximity sort). |
| `Future<List<TravelPlaceResult>> searchTravelPlaces({...})` | Place suggestions. |
| `Stream<List<Post>> streamUserPosts(String uid)` | Profile tab. |
| `Stream<List<Post>> streamUserQaAsked(uid, {limit})` | Profile QA-asked tab. |
| `Stream<List<Post>> streamUserQaAnswered(uid, {limit})` | Profile QA-answered tab. |
| `Future<void> deletePost(String postId)` | Author delete (also cascades comments/likes/reposts). |
| `Future<void> deletePostAsAdmin(String postId)` | Admin delete; updates author's `postsCount`. |
| `Future<void> updatePost(...)` | Edit caption / privacy. |
| `Future<void> toggleLike(String postId)` | Transactional toggle on `posts/{id}/likes/{uid}` + `likesCount`; fans out a notification with deterministic ID. |
| `Stream<bool> streamIsLiked(postId, {uid})` | |
| `Future<void> toggleRepost(String postId)` | Transactional toggle on `posts/{id}/reposts/{uid}` and `users/{uid}/reposts/{postId}`. |
| `Stream<bool> streamIsReposted(postId, {uid})` | |
| `Stream<int> streamRepostsCount(postId)` | |
| `Stream<List<String>> streamRepostUserIds(postId)` | |
| `Stream<List<Post>> streamUserReposts(String uid)` | |
| `Future<void> toggleSave(String postId)` | `users/{uid}/saved/{postId}`. |
| `Stream<bool> streamIsSaved(postId, {uid})` | |
| `Stream<List<Post>> streamUserSaved(String uid)` | |

Firestore: `posts/`, `posts/{id}/likes`, `posts/{id}/reposts`, `posts/{id}/comments`, `users/{uid}/saved`, `users/{uid}/reposts`, `postReports/`, `discussReports/`.

## Comments / QA

### [`comment_service.dart`](../../lib/src/services/comment_service.dart) — `CommentService`

Public + private (per-user, profanity-flagged) comments. Threads notifications via deterministic doc IDs. Throws `ProfanityEditRejected` when an edit would introduce profanity into a previously-clean public comment.

| Method | Purpose |
|---|---|
| `Stream<int> streamCommentsCount(String postId)` | Live count from the subcollection (never the cached `commentsCount`). |
| `Stream<List<Comment>> streamComments(postId, {viewerUid})` | Merge of public comments + the viewer's own private comments. Sorts: own first, then by likes desc, then by time desc. |
| `Future<void> addComment({...})` | Profanity check. If flagged, writes to `posts/{id}/privateComments/{viewerUid}/items/`; otherwise public. Fans out 5 different notification types (`comment`, `reply`, `qa_answer`, `qa_reply`, `comment_like`). |
| `Future<void> editComment({postId, commentId, newText, senderOnly, currentUid})` | Re-runs profanity; promotes private→public if cleaned, demotes public→reject if dirty (throws `ProfanityEditRejected`). |
| `Future<void> deleteComment({postId, commentId, senderOnly, currentUid})` | Decrements `commentsCount` for public; cleans up corresponding notifications. |
| `Future<void> toggleLikeComment({postId, commentId, uid})` | Transactional like; ups/downs `comment_like` notification. |
| `Stream<bool> streamIsCommentLiked({postId, commentId, uid})` | |
| `Stream<int> streamCommentLikesCount({postId, commentId})` | |
| `Stream<String?> streamUserAnswerReaction({postId, commentId, uid})` | "heart"/"broken" reaction on a QA answer. |
| `Future<void> setAnswerReaction({postId, commentId, uid, type})` | Transactional toggle; manages helpfulCount/unhelpfulCount + fan-out of `qa_answer_like` / `qa_answer_dislike` notifications. |

## Follow

### [`follow_service.dart`](../../lib/src/services/follow_service.dart) — `FollowService`

Follow / unfollow / accept-request / reject-request, plus side-effect: promoting a direct chat to "accepted" once both users become mutual followers.

| Method | Purpose |
|---|---|
| `Future<void> follow({currentUid, targetUid, isPrivate})` | Writes both `following/{targetUid}` and `followers/{currentUid}` with `status: 'pending' \| 'active'`. Fires `follow` or `follow_request` notification (deterministic IDs `follow_{actor}` / `follow_request_{actor}`). |
| `Future<void> unfollow({currentUid, targetUid})` | Deletes both edges; clears the matching notifications. |
| `Future<void> acceptFollowRequest({currentUid, requesterUid})` | Flips both edges to active, writes a `follow_accept` notification for the requester, deletes the original `follow_request` notification. Auto-promotes any existing direct chat to accepted. |
| `Future<void> rejectFollowRequest({currentUid, requesterUid})` | Deletes both edges and the request notification. |
| `Stream<bool> isFollowing({currentUid, targetUid})` | True only if `status != 'pending'`. |
| `Stream<bool> hasRequestedFollow({currentUid, targetUid})` | True only if `status == 'pending'`. |
| `Stream<List<String>> getFollowers(uid)` | Active only, newest first. |
| `Stream<List<String>> getFollowRequests(uid)` | Pending followers (= incoming requests). |
| `Stream<List<String>> getFollowing(uid)` | Active only. |

Internal: `_promoteDirectChatIfMutualFollow` — `chats/{chatId}.acceptedBy ∪= {a, b}` once both sides are active.

## Block

### [`block_service.dart`](../../lib/src/services/block_service.dart) — `BlockService`

Blocks stored as `users/{uid}.blockedUsers: [uid, ...]` array (NOT a subcollection — avoids rules complexity).

| Method | Purpose |
|---|---|
| `Future<void> blockUser({currentUid, targetUid})` | Batch: arrayUnion target into `blockedUsers`, also delete the 4 follower/following edges in both directions. |
| `Future<void> unblockUser({currentUid, targetUid})` | `arrayRemove`. |
| `Stream<bool> isBlocked({currentUid, targetUid})` | |
| `Stream<bool> isBlockedBy({currentUid, targetUid})` | |
| `Stream<List<String>> getBlockedUsers(uid)` | |

## Chat (1:1 + group)

### [`chat_service.dart`](../../lib/src/services/chat_service.dart) — `ChatService`

Big service. Models: `ChatMessage`, `ChatConversation`. Handles: deterministic 1:1 chat IDs (`uidA_uidB` sorted), mutual-follow auto-acceptance of new chats, profanity → sender-only messages, per-user message deletion, "delete for everyone", muting, auto-delete period, group create/rename/add/remove, on-disk message cache integration, decryption-failed placeholder.

Selected methods:

| Method | Purpose |
|---|---|
| `String buildChatId(String a, String b)` | Sorted concatenation. |
| `Future<String> openChat({currentUid, otherUid})` | Idempotent; creates the chat doc on first contact. Pre-accepts both sides if `_isMutualFollow`. |
| `Future<void> sendMessage({...18 params...})` | Profanity-filter; if flagged, message is `senderOnly` (only sender's UID in `visibleToUids`). Computes recipients for unread bookkeeping. Atomically writes the message doc + chat summary in a batch. |
| `Future<void> markSeen({chatId, uid})` | Resets unread + appends `uid` to `seenBy` on the last 50 messages (FieldValue.arrayUnion). |
| `Stream<List<ChatMessage>> streamMessages(chatId, {uid})` | Emits the cached snapshot FIRST (via [`MessageCache`](#message_cachedart--messagecache-singleton)) so opening a chat feels instant, then takes over with the live Firestore stream. Writes the rolling last-20-message snapshot to disk after each emission. |
| `Stream<List<ChatConversation>> streamInbox(uid)` | All conversations, hydrated with latest-visible-message + derived unread count. Hides empty 1:1 chats; groups stay visible even when empty. |
| `Stream<List<ChatConversation>> streamRequests(uid)` | Inbox filtered to `isRequest && !mutualFriend`. |
| `Stream<List<ChatConversation>> streamAcceptedInbox(uid)` | Inverse. |
| `Future<String> createGroup({creatorUid, memberUids, groupName, groupAvatarUrl?})` | Creates a `kind: 'group'` chat doc. |
| `Future<void> addGroupMember({chatId, uid})` | Admin-only. |
| `Future<void> leaveOrRemoveGroupMember({chatId, uid})` | |
| `Future<void> renameGroup({chatId, name})` | Admin-only. |
| `Future<void> deleteMessageForMe({chatId, messageId, uid})` | Adds to `deletedForUids`. |
| `Future<void> deleteMessageForEveryone({chatId, messageId, uid})` | Sender-only. Sets `deletedForEveryone: true`. |
| `Future<void> deleteChat(String chatId)` | Wipes messages in 400-doc batches, then chat doc, then calls `MessageCache.instance.clear(chatId)`. |
| `Future<void> deleteGroup(String chatId)` | Wraps `deleteChat`. |
| `Future<void> setMuted({chatId, uid, bool})` | Toggles `mutedFor` (read by backend FCM dispatcher). |
| `Future<void> setAutoDeletePeriod({chatId, period})` | `autoDeleteSeconds` field (read by a future scheduled job). |

Internal: `_previewTextForMessage` resolves the inbox-tile preview text for stickers/voice/file/photo/video/location/storyReply/sharedPost. `_isVisibleToUser` honors `deletedForUids`, `deletedForEveryone`, `visibleToUids` (for sender-only profanity messages).

### [`message_cache.dart`](../../lib/src/services/message_cache.dart) — `MessageCache` (singleton)

On-disk per-chat cache. **Wiped on logout** (called from `_MyAppState.build` in `main.dart` when `previousUser != null && nextUser == null`).

- Singleton: `MessageCache.instance`.
- Two layers per chat:
  - **Payload cache** `{chatId}.payloads.json` — `{msgId: decryptedJsonString}`, capped at `maxEntries = 20`.
  - **Snapshot cache** `{chatId}.snapshot.json` — JSON of the last rendered `List<ChatMessage>`.
- Files live under `getApplicationDocumentsDirectory()/message_cache/`. Chat IDs are sanitized via `_safeId` to alphanumeric-underscore-hyphen.
- Methods: `loadPayloads`, `savePayloads`, `loadSnapshot`, `saveSnapshot`, `clear(chatId)` (memory + disk), `clearAll()` (wipe everything on signout).

### [`typing_service.dart`](../../lib/src/services/typing_service.dart) — `TypingService`

Firebase Realtime Database, path `typing/{chatId}/{uid}`. Boolean flag with `onDisconnect().remove()` to clean up stale indicators when the socket drops.

| Method | Purpose |
|---|---|
| `Future<void> setTyping(chatId, uid, isTyping)` | Sets/removes the typing flag. |
| `Stream<bool> listenTyping(chatId, otherUid)` | |

### [`presence_service.dart`](../../lib/src/services/presence_service.dart) — `PresenceService`

Firebase Realtime Database, path `presence/{uid}`. See `08-lifecycle-and-presence.md` for the full picture.

| Method | Purpose |
|---|---|
| `Future<void> setOnline(String uid)` | Updates `{online: true, lastSeen: ServerValue.timestamp}` and registers `onDisconnect().update({online: false, lastSeen: now})`. |
| `Future<void> setOffline(String uid)` | Explicit offline (on signout or background). |
| `Stream<PresenceData> listenPresence(String uid)` | Live presence. `PresenceData.statusText` formats "Online" / "last seen 5m ago". |

### [`reaction_service.dart`](../../lib/src/services/reaction_service.dart) — `ReactionService`

Per-message emoji reactions at `{parentPath}/{messageId}/reactions/{uid}`. Bundled emoji set: `kReactionEmojis = ['❤️', '😂', '😮', '😢', '🔥', '👍']`.

| Method | Purpose |
|---|---|
| `Future<void> toggle({parentPath, messageId, emoji})` | Same emoji → delete; different → replace. |
| `Stream<String?> streamMyReaction({parentPath, messageId})` | |
| `Stream<Map<String, int>> streamReactionCounts({parentPath, messageId})` | Aggregated. |

## Notifications + push

### [`notification_service.dart`](../../lib/src/services/notification_service.dart) — `NotificationService`

In-app notifications at `notifications/{uid}/items/{notifId}`. Used by every cross-user side effect (follow, like, comment, qa_*, role_update, event_invited, event_removed, event_approved, event_rejected, new_event).

| Method | Purpose |
|---|---|
| `Stream<List<AppNotification>> getNotifications(uid)` | Limit 50. |
| `Stream<int> getUnreadCount(uid)` | |
| `Future<void> markRead(uid, notifId)` | |
| `Future<void> markNotificationsRead(uid, ids)` | Batch. |
| `Future<void> markUnread(uid, notifId)` | |
| `Future<void> updateNotificationStatus(uid, notifId, status)` | Sets `status` (`'accepted'`/`'rejected'`) + auto-marks read. |
| `Future<void> markAllRead(uid)` | Batch. |
| `Future<void> createNotification({targetUid, type, actorUid, targetId?, commentId?})` | Random-id write. |
| `Future<void> createSystemNotification({targetUid, type, title, subtitle?, targetId?})` | Actor-less notifications (`role_update`, `new_event`). |
| `Future<void> upsertNotification({targetUid, docId, type, actorUid, targetId?, commentId?})` | Deterministic ID — repeated identical actions never duplicate. |
| `Future<void> removeNotificationById(targetUid, docId)` | Used to clean up on unlike/unfollow. |
| `Future<void> deleteNotification(uid, notifId)` | |

### [`fcm_service.dart`](../../lib/src/services/fcm_service.dart) — `FcmService`

Push tokens + foreground/background routing.

- Top-level `_onBackgroundMessage` (annotated `@pragma('vm:entry-point')`) — no body; the OS draws the notification itself.
- Broadcast stream `events: Stream<FcmMessageEvent { message, openedApp }>`.
- `init(uid)`:
  - Registers `_onBackgroundMessage`.
  - Requests notification permission (iOS / Android 13+).
  - Sets foreground presentation options to alert+badge+sound.
  - On iOS/macOS, polls `getAPNSToken()` up to 10 × 500ms before calling `getToken()` (avoids cold-start race).
  - Persists FCM token to `users/{uid}.fcmTokens` via `arrayUnion`.
  - Subscribes to `onTokenRefresh`.
  - Registers `onMessage` (foreground) and `onMessageOpenedApp` listeners that emit `FcmMessageEvent`s.
  - Calls `getInitialMessage` and emits if non-null.
- `removeToken(uid)` — `arrayRemove` the current token from `users/{uid}.fcmTokens` (called on signout).

## Stories

### [`story_service.dart`](../../lib/src/services/story_service.dart) — `StoryService`

Models: `Story` (image / video / text / shared-post variants, with optional text overlays), `StoryViewer`.

| Method | Purpose |
|---|---|
| `Future<String> createStory({imageUrl, sharedPostId?, videoUrl?, videoTrimStartMs?, videoTrimEndMs?, textContent?, backgroundColor?, textColor?, textBorderStyle?, overlays})` | Writes `stories/` with `expiresAt = now + 24h`. |
| `Stream<List<Story>> streamActiveStories()` | `expiresAt > now`. |
| `Future<bool> hasViewed(String storyId)` | |
| `Future<void> deleteStory(String storyId)` | |
| `Future<void> recordView(storyId, {authorUid})` | Writes `stories/{id}/viewers/{viewerUid}`. |
| `Stream<int> streamViewersCount(storyId)` | |
| `Stream<List<StoryViewer>> streamViewers(storyId)` | |
| `Future<void> toggleLike(String storyId)` | Notification to story author. |
| `Stream<bool> streamIsLiked(storyId, {uid})` | |
| `Stream<int> streamLikesCount(storyId)` | |
| `Stream<List<StoryViewer>> streamLikers(storyId)` | |
| `Future<void> addComment({storyId, ...})` | + notification. |
| `Stream<List<StoryComment>> streamComments(storyId)` | |
| `Future<void> deleteComment({storyId, commentId, ...})` | |

### [`own_story_seen_service.dart`](../../lib/src/services/own_story_seen_service.dart) — `OwnStorySeenService` (+ providers)

Local SharedPreferences (`own_story_seen_{id}`, `own_story_seen_viewers_{id}`). Tracks whether the AUTHOR has opened their own story and the viewers count at that moment, so the home rail can dim the ring AND re-highlight when new viewers arrive. NOT written to Firestore (Instagram-style: viewers list shouldn't include the author). See providers section above.

## Polls

### [`poll_service.dart`](../../lib/src/services/poll_service.dart) — `PollService`

Polls live at `{parentPath}/polls/{pollId}` and `.../votes/{voterUid}` where parentPath is `"chats/{id}"` or `"eventChats/{id}"`. Visibility: `public` (votes shown) or `secret` (counts only).

| Method | Purpose |
|---|---|
| `Future<String> createPoll({parentPath, question, options, visibility})` | Clamps to 10 options. |
| `Stream<List<Poll>> streamPolls(parentPath)` | |
| `Stream<List<PollVote>> streamVotes(parentPath, pollId)` | |
| `Stream<PollVote?> streamMyVote(parentPath, pollId)` | |
| `Future<void> castVote({parentPath, pollId, optionIndex})` | |
| `Future<void> closePoll(parentPath, pollId)` | |
| `Future<void> deletePoll(parentPath, pollId)` | |

## Contact requests (Contact-us)

### [`contact_request_service.dart`](../../lib/src/services/contact_request_service.dart) — `ContactRequestService`

Threaded contact-us / "promote me to organization admin" requests. Models: `ContactRequest`, `ContactRequestMessage`. Enums: `ContactRequestType { message, organization }`, `ContactRequestStatus { open, answered, promoted, revoked }`. Throws `ContactRequestDailyLimitException` when a user has already opened one today (UTC-day key on `users/{uid}.lastContactRequestDay`).

| Method | Purpose |
|---|---|
| `Future<String> submit({userUid, userEmail, userName, type, firstMessage})` | Transaction: enforces 1/day limit + writes the parent doc + first message. |
| `Future<void> sendMessage({requestId, senderUid, senderIsAdmin, body})` | Appends to `contactRequests/{id}/messages`, flips `unreadByUser`/`unreadByAdmin`, auto-sets status to `answered` on admin reply (unless already `promoted`/`revoked`). |
| `Future<void> setType({requestId, type})` | |
| `Stream<List<ContactRequest>> streamMyRequests(userUid)` | |
| `Stream<List<ContactRequest>> streamAll()` | Admin. |
| `Stream<List<ContactRequestMessage>> streamMessages(requestId)` | |
| `Future<void> markRead({requestId, readerIsAdmin})` | |
| `Future<void> promoteToOrgAdmin({requestId, userUid})` | Flips role + writes a `role_update` system notification. |
| `Future<void> revokeOrgAdmin({requestId, userUid})` | Cascade-deletes all events created by that user (and their event chats, registrations), restores `role: 'user'`. |
| `Future<void> deleteRequest(String requestId)` | Admin delete (only the parent — rules forbid deleting messages). |

## Events

### [`event_registration_service.dart`](../../lib/src/services/event_registration_service.dart) — `EventRegistrationService`

Per-event signup requests at `eventRegistrations/{eventId}_{userUid}`. Models: `EventRegistration`, enum `RegistrationStatus { pending, approved, rejected }`.

| Method | Purpose |
|---|---|
| `Future<void> submit({eventId, eventTitle, name, email, phone, countryCode})` | Deterministic ID enforces one in-flight per event. |
| `Stream<List<EventRegistration>> streamPending()` | All pending (admin). |
| `Stream<List<EventRegistration>> streamPendingForEvent(eventId)` | Per-event admin view. |
| `Stream<EventRegistration?> streamMine(eventId)` | |
| `Future<void> approve(EventRegistration reg)` | Marks approved + `event_approved` notification. |
| `Future<void> reject(EventRegistration reg)` | Marks rejected + `event_rejected` notification. |

### [`event_chat_service.dart`](../../lib/src/services/event_chat_service.dart) — `EventChatService`

Per-event group chats at `eventChats/{eventId}` with `messages/` and `members/` subcollections. Models: `EventChatMessage`, `EventChatSummary`.

| Method | Purpose |
|---|---|
| `Future<void> sendMessage({eventId, text, imageUrl?})` | Admin-only (Firestore rules enforce). |
| `Stream<List<EventChatMessage>> streamMessages(eventId)` | |
| `Stream<List<EventChatSummary>> streamMyEventChats(uid)` | Combines two streams (member-via-`collectionGroup('members')` + admin-owned chats) using an internal `_combineLatest2`. |
| `Future<void> markSeen(String eventId)` | `members/{uid}.lastSeenAt = serverTimestamp`. |
| `Stream<String?> streamAdminUid(eventId)` | |
| `Stream<List<Map>> streamMembers(eventId)` | |
| `Future<void> addMember({eventId, uid})` | Admin-only. Fires `event_invited` notification. |
| `Future<void> removeMember({eventId, uid, notifyRemovedUser})` | Admin or self. Fires `event_removed` notification if admin kicked. |
| `Future<void> leaveGroup(String eventId)` | Wrapper around `removeMember` for the current user. |
| `Future<void> setMuted({eventId, uid, muted})` | `mutedFor` array. |
| `Future<void> deleteEventGroup(String eventId)` | Admin-only — wipes messages + members in 400-batch loops, then the chat doc. |

## Profile visitors

### [`profile_visitor_service.dart`](../../lib/src/services/profile_visitor_service.dart) — `ProfileVisitorService`

Tracks "who viewed my profile" at `users/{ownerUid}/visitors/{visitorUid}` (one doc per visitor, refreshed on each visit). Author's own views NOT recorded.

| Method | Purpose |
|---|---|
| `Future<void> recordVisit(String ownerUid)` | `set(merge)` with `lastVisitedAt = serverTimestamp`, `visitCount = increment(1)`. No-op for self. |
| `Stream<List<ProfileVisitorEntry>> streamVisitors(ownerUid)` | Newest first. |
| `Stream<int> streamVisitorCount(ownerUid)` | |

## Storage (Supabase via Edge Function)

### [`storage_service.dart`](../../lib/src/services/storage_service.dart) — `StorageService`

All media uploads go through a Supabase Edge Function (`issue-upload-url`) — NOT Firebase Storage. Reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from `.env`.

| Method | Bucket / kind |
|---|---|
| `uploadAvatar(file)` | `avatars/avatar` |
| `uploadCover(file)` | `avatars/cover` |
| `uploadPostImage(file)` | `posts/post` |
| `uploadPostVideo(file)` | `posts/post-video` |
| `uploadChatImage(file, chatId)` | `posts/chat`, subPath=chatId |
| `uploadChatAudio(file, chatId)` | `posts/audio`, subPath=chatId |
| `uploadStoryImage(file)` | `posts/story` |
| `uploadStoryVideo(file)` | `posts/story-video` (falls back to `post-video` if the edge function rejects with "bad kind") |
| `uploadChatVideo(file, chatId)` | `posts/chat-video`, subPath=chatId |
| `uploadChatFile(file, chatId)` | `posts/chat-file`, subPath=chatId |

Throws `StorageException` on edge-function failure. Internal `_uploadViaEdge` POSTs to issue an upload URL then uploads the bytes.

## Profanity filter

### [`profanity_filter_service.dart`](../../lib/src/services/profanity_filter_service.dart) — `ProfanityFilterService`

In-memory 10-minute cached load of `adminConfig/app.profanityWordsEn`. Falls back to a hard-coded `_fallbackWords` set when the config read fails. Normalization: lowercase + strip non-letters.

| Method | Purpose |
|---|---|
| `Future<List<String>> findMatches(String text)` | Splits text on non-letters and intersects with the word set. Returns sorted matches. |

Consumed by `PostService.createPost`, `ChatService.sendMessage`, `CommentService.addComment` / `editComment`.

## Translation

### [`translate_service.dart`](../../lib/src/services/translate_service.dart) — `TranslateService`

Client-side translation with provider routing. Persisted on-disk LRU-ish cache (`translate_cache_v1` in SharedPreferences, capped at 1000 entries — dropped wholesale on overflow). Single source of truth for translation languages: `kTranslateLanguages` (60+ entries, each with `code`, `label`, optional `stt` STT locale, `rtl` flag).

- Provider routing in `_buildProviderList`:
  - Kurdish (ckb / kmr / ku) involved → Azure first, MyMemory, Gemini (order is deterministic, no rotation).
  - Otherwise → Gemini → Langbly → MyMemory → FreeAPITools → Azure (rotated round-robin via `_providerIndex`).
- Each provider has its own HTTP method (`_callAzure`, `_callGemini`, `_callLangbly`, `_callMyMemory`, `_callFreeAPITools`) with API key from `.env` (`AZURE_TRANSLATOR_KEY` + region, `GEMINI_API_KEY`, `LANGBLY_API_KEY`, `FREEAPITOOLS_API_KEY`).
- Tag `[translate]` on every debug print.
- `static String userFriendlyErrorMessage(Object error)` — maps exception strings to a localized-ish copy.
- `static Future<void> clearCache()` — memory + disk.
- `Future<String> translateText({text, sourceLang, targetLang})` — heuristically force-detects Kurdish from text characters (`ەۆڕڵڎڤێ` for Sorani, `çêîşû` for Kurmanji) when `sourceLang == 'auto'`.

## Stickers

### [`sticker_service.dart`](../../lib/src/services/sticker_service.dart) — `StickerService`

Recents + favorites in SharedPreferences (`recent_stickers` cap 30, `favorite_stickers`). Custom sticker packs in Firestore (`users/{uid}/stickerPacks/{packId}`) with images in Firebase Storage (`users/{uid}/stickers/{packId}/sticker_{ts}.webp`).

| Method | Purpose |
|---|---|
| `Future<List<String>> getRecentStickers()` | |
| `Future<void> addRecentSticker(stickerUrl)` | |
| `Future<List<String>> getFavoriteStickers()` | |
| `Future<void> toggleFavorite(stickerUrl)` | |
| `Future<bool> isFavorite(stickerUrl)` | |
| `Future<String> createCustomPack({uid, name})` | |
| `Future<String> uploadCustomSticker({uid, packId, imageFile})` | Uploads webp + arrayUnion the URL into the pack doc. |
| `Future<void> removeCustomSticker({uid, packId, stickerUrl})` | |
| `Future<void> deleteCustomPack({uid, packId})` | Best-effort storage delete then doc delete. |
| `Stream<List<CustomStickerPack>> streamCustomPacks(uid)` | |

### [`sticker_data.dart`](../../lib/src/services/sticker_data.dart)

Static data only. Defines `StickerPack`, `Sticker`, and `const kBuiltInStickerPacks` (categories: cute animals, meme reactions, celebrations, love, greetings, emotions, cool, kawaii). Built-in stickers are emoji strings rendered large; custom stickers are Storage URLs.

## City picker

### [`city_service.dart`](../../lib/src/services/city_service.dart)

Shared world-city picker. Backed by the offline `country_state_city` package (~40k cities). Exposes:
- `normalizeCitySearch(String)` — diacritic-insensitive normalization with custom mappings (`İ → i`, `ş → s`, etc.).
- `CityOption` model with precomputed `searchHaystack` and `displayLabel`.
- `worldCitiesProvider` (Riverpod) — one-shot lazy load + sort.
- `rankCities(cities, rawQuery)` — exact → prefix → word-boundary → substring scoring.
- `showCityPicker(context, {initialQuery, showNearby})` + `kCityPickerNearby` sentinel.
- `CityPickerField` — read-only widget that opens the sheet.

## Patterns across the codebase

- **Best-effort notifications**: cross-user side effects wrap `_notifications.upsertNotification(...)` in a `try {} catch (_) {}` so a failed notification never blocks the write.
- **Deterministic notification IDs**: `comment_{postId}_{commentId}_{actorUid}`, `follow_{actor}`, `follow_request_{actor}`, `new_event_{eventId}`, `qa_answer_{postId}_{commentId}_{actor}`, etc. — lets the unlike/unfollow path delete the exact notification by ID without scanning.
- **Cascade-delete batches**: 400 ops per batch (FB cap is 500) with a while-loop until empty.
- **Spark plan stand-ins**: Several services contain "if there were a Cloud Function this would do X" client-side fallbacks (event notification fan-out in `AdminService._fanOutNewEventNotifications`, comment notification fan-out in `CommentService.addComment`).

## Related files

- All services in [`lib/src/services/`](../../lib/src/services/).
- Provider wrappers: [`lib/src/providers/`](../../lib/src/providers/) — see `02-state-providers.md`.
- Models live next to their service: `ChatMessage`/`ChatConversation` in `chat_service.dart`, `Story`/`StoryViewer` in `story_service.dart`, etc. Standalone model files are under [`lib/src/features/model/`](../../lib/src/features/model/).
