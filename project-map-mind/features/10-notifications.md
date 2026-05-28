# Notifications

## What this feature does
A single in-app inbox screen (`NotificationScreen`) categorizes every notification into one of three buckets — **Activity** / **Follow** / **Event** — controlled by a `_NotificationCategory` enum and a `_categoryForType(String type)` switch. Notifications come from two sources: in-app `notifications/{uid}/items` Firestore subcollection docs (written by `NotificationService` from client logic or by Cloud Functions), and FCM push messages (received in foreground via `FirebaseMessaging.onMessage`, and from a terminated/background tap via `onMessageOpenedApp` + `getInitialMessage`). `FcmService` requests permission, persists the device's FCM token under the user's `fcmTokens` array, and broadcasts `FcmMessageEvent`s for the rest of the app to deep-link from. Read state is tracked per-doc (`read:true/false`); the screen has a deliberately unusual "mark as read on category close" UX — opening a category and switching away (or closing the screen) batch-marks every previously-unread notification in that category as read.

## Key screens / widgets
- [notification_screen.dart](../../lib/src/features/screens/notification_screen.dart) — 1 300-line full screen. Top: 3-pill category selector (Activity / Follow / Event). Body: filtered list. Long-press a tile → action menu (`markUnread`, `delete`). Each tile is a `NotificationTile` instance with type-specific leading icon + trailing widget (avatar / post thumb / accept-reject buttons).
- [notification_tile.dart](../../lib/src/features/widgets/notification_tile.dart) — generic tile shell. `trailingType` (`NotificationType.image | accept | none`) + optional `trailingWidget` override for callers that want to render a fetched post thumb.

## Categories (3 enum values)
- **Activity** (default category opened on entry) — `like`, `reply`, `comment`, `comment_like`, `qa_answer`, `qa_reply`, `qa_answer_like`, `qa_answer_dislike`, `repost`, `story_like`, `story_comment`, `story_reply`, `message`.
- **Follow** — `follow`, `follow_request`, `follow_accept`.
- **Event** — `event_approved`, `event_rejected`, `event_invited`, `event_removed`, `new_event`, `role_update`.

Any unknown `type` is treated as Activity (default fallthrough in `_categoryForType`).

## `AppNotification` doc shape (`notifications/{uid}/items/{notifId}`)
- `type` — one of the strings above (`unknown` fallback).
- `actorUid` — who triggered it (empty string for system notifications).
- `targetId` — `postId` for `like` / `comment` / etc., `eventId` for `new_event`.
- `commentId` — when set, tapping the notification opens the post and scrolls to + highlights the specific comment for ~3 s. Set for `reply` / `qa_reply`.
- `read: bool`.
- `status` — `'accepted'`, `'rejected'`, … (used by follow requests).
- `createdAt: Timestamp`.
- `title` / `subtitle` — system notifications (e.g. `new_event` stores event title here so there's no actor user lookup needed).

## Mark-as-read flow (`_markCategoryReadWhenClosed`)
1. On entry, the Activity category is marked `_opened`.
2. Switching to another category: all unread items in the **previously open** category are batch-marked as read via `NotificationService.markNotificationsRead(uid, ids)`.
3. A category, once "closed" (the user navigated away from it), is added to `_markedClosedCategories`; re-entering and re-leaving won't fire the same batch twice in a single visit.
4. Tapping a single notification also marks just that one as `markRead`.
5. There's no global "mark all" CTA in the screen; the per-category close handles that.

## Synthetic follow-request unread count
- The unread badge on the Follow pill includes a synthetic count: any `users/{uid}/followRequests` entries that **don't already** have a persisted `follow_request` notification doc are counted as 1 unread each. This matters because the legacy follow-request system pre-dates the persisted notification — `followRequestsProvider(uid)` + `notificationsProvider` are merged into the badge.

## Notification creation paths (`NotificationService`)
- `createNotification(targetUid, type, actorUid, targetId, commentId)` — appends a new doc.
- `createSystemNotification(targetUid, type, title, subtitle, targetId)` — system (no `actorUid`).
- `upsertNotification(targetUid, docId, type, actorUid, targetId, commentId)` — deterministic id so like / unlike / like doesn't create duplicates. Used by `qa_answer`, `qa_reply`, `reply`, `comment`, `comment_like`, `like`.
- `removeNotificationById(targetUid, docId)` — used on unlike to clean up.
- `updateNotificationStatus(uid, notifId, status)` — also auto-marks read.
- `markRead`, `markUnread`, `markNotificationsRead`, `markAllRead`.

## Deep linking (notification tap)
Each tile's `onTap` resolves to:
- `like` / `comment` / `comment_like` / `repost` → `PostDetailScreen(postId: targetId, openComments: type=='comment', highlightCommentId: commentId, highlightAuthorUid: actorUid)`.
- `reply` / `qa_reply` → `PostDetailScreen` with `highlightCommentId` → `CommentScreen` auto-opens and scrolls.
- `qa_answer` / `qa_answer_like` / `qa_answer_dislike` → `QaThreadScreen(post: …, pinCommentId: commentId)`.
- `follow` / `follow_accept` → `UserProfileScreen(uid: actorUid)`.
- `follow_request` → in-tile Accept / Reject buttons → `updateNotificationStatus(status: 'accepted'|'rejected')`.
- `new_event` / `event_invited` → opens `EventDetail` or `EventUnavailableScreen` if the event no longer exists.
- `event_approved` / `event_rejected` / `event_removed` / `role_update` → toast or settings deep link.
- `story_like` / `story_comment` / `story_reply` → `StoryViewerScreen`.
- `message` → `ChatScreen`.

## FCM integration (`FcmService`)
- `init(uid)` (called from `main.dart` after sign-in):
  - Registers top-level `_onBackgroundMessage` (no-op — relies on OS-rendered system notification from the payload).
  - Requests notification permission.
  - On iOS/macOS, **polls `getAPNSToken()` up to 10 × 500 ms** because `getToken()` fails before APNS is ready on first launch.
  - On success, `_saveToken(uid, token)` arrayUnion's the token into `users/{uid}.fcmTokens`.
  - Listens to `onTokenRefresh` and re-saves.
  - Registers `onMessage` (foreground) and `onMessageOpenedApp` (tap-to-open) handlers, broadcasting as `FcmMessageEvent` on a global `_eventsController` stream.
  - Re-emits `getInitialMessage` if the app was launched by tapping a notification while terminated.
- `removeToken(uid)` — called on sign-out; arrayRemove's the current token so the device doesn't keep receiving the previous user's pushes.
- The `_listenersRegistered` static guard prevents double-registering on hot reload.

## Firestore collections touched
- `notifications/{uid}/items` — all in-app notification docs.
- `users/{uid}.fcmTokens` — device tokens (array union/remove).
- `users/{uid}/followRequests` — read for the synthetic follow unread count.

## Services used
- [notification_service.dart](../../lib/src/services/notification_service.dart) — all CRUD + read-state.
- [fcm_service.dart](../../lib/src/services/fcm_service.dart) — token + event broadcasting.
- [follow_providers.dart](../../lib/src/providers/follow_providers.dart) — `followRequestsProvider`.
- [notification_providers.dart](../../lib/src/providers/notification_providers.dart) — `notificationsProvider`, `unreadActivityCountProvider`.

## Non-obvious business rules
- Live stream limited to 50 most recent items (`NotificationService.getNotifications`).
- Read state batching closes on **category close**, not on tap — supporting "scan and dismiss in bulk".
- Long-press to mark-as-unread or delete a tile.
- Deterministic doc id pattern: `like_${postId}_${actorUid}`, `comment_${postId}_${commentId}_${actorUid}`, etc. (visible in `CommentService.addComment` calling `upsertNotification`).
- System notifications carry their copy on the doc (`title`, `subtitle`) so no actor doc lookup is needed.
- Synthetic follow-unread count fires from `followRequestsProvider`, separate from persisted `follow_request` notification docs.
- `_onBackgroundMessage` is intentionally a no-op — the OS shows the payload automatically; the in-app handler only acts on foreground / opened-app events.
- The `commentId` field is what makes a tap on a `reply` notification scroll directly to the new reply, instead of just opening the post.

## Localization
- `notification_screen.dart`: ~65 keys.
- `notification_tile.dart`: ~2.

## Related files
- `lib/src/features/screens/notification_screen.dart`
- `lib/src/features/widgets/notification_tile.dart`
- `lib/src/services/notification_service.dart`
- `lib/src/services/fcm_service.dart`
- `lib/src/providers/notification_providers.dart`
- `lib/src/providers/admin_report_notifications_provider.dart`
- `lib/src/providers/follow_providers.dart`
