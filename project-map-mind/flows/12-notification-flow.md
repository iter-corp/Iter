# Flow 12 — Notifications and FCM push routing

Two halves: (1) how a notification doc gets created in Firestore (and what happens after), and (2) how the user actually sees / interacts with a notification — in-app and out-of-app.

## Sequence — full path for "user A likes user B's post"

```mermaid
sequenceDiagram
  participant A as User A (actor)
  participant Client as Client (PostService)
  participant FS as Firestore
  participant CF1 as onLikeCreate
  participant CF2 as sendPushOnNotificationCreate
  participant FCM as FCM
  participant B as User B (recipient device)
  participant NScr as NotificationScreen

  A->>Client: tap heart
  Client->>FS: posts/{id}/likes/{A}.set; likesCount: +1
  Client->>FS: notifications/{B}/items/like_{A}_{id}.set (client write, deterministic id)
  FS-->>CF1: onCreate posts/{id}/likes/{A}
  CF1->>FS: notifications/{B}/items/{auto-id}.add({type:'like'}) (CF write — auto id)
  FS-->>CF2: onCreate notifications/{B}/items/{any-id}
  CF2->>FS: read users/{B}.fcmTokens
  CF2->>FCM: sendEachForMulticast({tokens, notification:{title:'New like', body:'…'}, data:{type, actorUid, targetId}})
  alt B is foregrounded
    FCM-->>B: onMessage event
    B->>B: snackbar + badge update via NotificationScreen
  else B is backgrounded / cold
    FCM-->>B: OS displays system notification
    B->>FCM: tap notification
    FCM-->>B: onMessageOpenedApp / getInitialMessage
    B->>B: main.dart._handleFcmEvent routes by type
  end
  B->>NScr: open NotificationScreen
  NScr->>FS: notifications/{B}/items.orderBy(createdAt desc).limit(50)
  NScr->>B: render grouped by category
```

## In-app: the notification document model

`AppNotification` ([`notification_service.dart`](../../lib/src/services/notification_service.dart)) holds:
- `id`
- `type` — one of `follow`, `follow_request`, `follow_accept`, `like`, `comment`, `comment_like`, `reply`, `qa_answer`, `qa_reply`, `qa_answer_like`, `qa_answer_dislike`, `story_like`, `story_comment`, `story_reply`, `message`, `new_event`, `event_approved`, `event_rejected`, `event_invited`, `role_update`, `repost`
- `actorUid` (empty for system notifications like `new_event` or `role_update`)
- `targetId` — postId for like/comment, eventId for new_event, chatId for message, etc.
- `commentId` — optional, for navigation that should land on a specific comment
- `read: bool`
- `status` — optional ('accepted' / 'rejected' for follow_request)
- `createdAt`
- `title` / `subtitle` — used by system notifications that have no actor (e.g. event title for `new_event`)

## Who writes notification docs

Two parallel writers exist:

1. **Client writes** via `NotificationService`:
   - `createNotification` (auto-id) — used for `follow_accept`, `story_comment`, `story_reply`, `event_*` (admin actions).
   - `createSystemNotification` (auto-id, with `title`/`subtitle`) — used for `role_update`.
   - `upsertNotification` (deterministic id) — used for `like`, `comment`, `reply`, `qa_answer`, `qa_reply`, `qa_answer_like`, `qa_answer_dislike`, `comment_like`, `story_like`, `repost`, `follow`, `follow_request`.
   - `removeNotificationById` (deterministic id) — cleanup on unlike / unfollow / un-react.

2. **Cloud Functions** ([`functions/src/notifications.ts`](../../functions/src/notifications.ts), [`likes.ts`](../../functions/src/likes.ts), [`comments.ts`](../../functions/src/comments.ts), [`follows.ts`](../../functions/src/follows.ts), [`messages.ts`](../../functions/src/messages.ts), [`events.ts`](../../functions/src/events.ts)):
   - Some use the same deterministic ids as the client → writes collapse via `set(merge)`.
   - Some use auto-ids → creates a parallel duplicate notification doc alongside the client's deterministic one.

> **Net effect.** Each "like" or "regular comment" produces TWO notification docs on the recipient (one client deterministic, one CF auto-id). The deterministic doc is the one that gets cleaned up when the action is reversed. The auto-id doc leaks. The push fires once per doc creation, so the recipient sees two FCM pushes per like — unless the OS coalesces by `tag` (it doesn't, by default).
>
> All Q&A reaction notifications (`qa_answer`, `qa_reply`, `qa_answer_like`, etc.) use the SAME deterministic id on both writers, so they collapse cleanly. Same for follow/follow_request notifications. The duplicate-doc issue is limited to `like` and regular post `comment` types.

## FCM push side

[`sendPushOnNotificationCreate`](../../functions/src/notifications.ts):
1. Triggered on `notifications/{uid}/items/{notificationId}` create.
2. Reads `users/{uid}.fcmTokens` (set/refreshed by [`FcmService`](../../lib/src/services/fcm_service.dart) on every login + `onTokenRefresh`).
3. Resolves actor username from `users/{actorUid}` (only when `actorUid` is non-empty).
4. Switches on `data.type` to compute `{title, body}`. Types not in the switch fall through to:
   - `title = 'COIL'`
   - `body = '{actorName} interacted with you'`
   Currently un-mapped types: `comment_like`, `repost`, `story_like`, `story_comment`, `story_reply`, `follow_request`, `follow_accept`, `event_approved`, `event_rejected`, `event_invited`, `role_update`. All show generic copy.
5. `admin.messaging().sendEachForMulticast({tokens, notification: {title, body}, data: {type, actorUid, targetId}})`.

## Client receive paths

[`FcmService.init`](../../lib/src/services/fcm_service.dart):
- Requests OS permission on iOS / Android 13+ / web.
- Persists the device FCM token to `users/{uid}.fcmTokens` (array union).
- Registers three listeners that all funnel into a broadcast stream `events`:
  - `FirebaseMessaging.onMessage` (in-foreground) → `FcmMessageEvent(openedApp: false)`.
  - `FirebaseMessaging.onMessageOpenedApp` (push tapped while backgrounded) → `openedApp: true`.
  - `FirebaseMessaging.getInitialMessage()` (push tapped to cold-start the app) → `openedApp: true`.
- Background message handler (`_onBackgroundMessage`) is a top-level no-op — the OS displays the notification payload automatically.

[`main.dart` `_handleFcmEvent`](../../lib/main.dart) (lines 200–214):
```dart
if (!event.openedApp || !mounted) return;
// de-dupe by messageId
final type = data['type'];
final targetId = data['targetId'];
if (type == 'new_event' && targetId != null) {
  unawaited(_openEventDetailFromPush(targetId));
}
```

Currently only `type == 'new_event'` is explicitly routed from a push tap to a screen. Other types open the app to its current location; the user has to navigate to the relevant content manually (or via the in-app NotificationScreen). Tapping the notification row INSIDE the app, however, does route — see [`NotificationScreen`](../../lib/src/features/screens/notification_screen.dart) handlers per category.

## In-app NotificationScreen

[`NotificationScreen`](../../lib/src/features/screens/notification_screen.dart):
- Streams `notifications/{uid}/items.orderBy(createdAt desc).limit(50)` via `NotificationService.getNotifications(uid)`.
- Groups by category (likes, comments, follows, messages, events…). `_categoryForType` maps each notification type into a category.
- Selecting a category opens that tab; closing the tab batch-updates all visible items to `read: true` via `markNotificationsRead`.
- Tapping a notification routes to:
  - `like` / `comment` / `reply` / `comment_like` / `qa_*` → `PostDetailScreen` (or `QaThreadScreen` for QA) with `highlightCommentId` set.
  - `follow` / `follow_accept` → user profile.
  - `follow_request` → request screen with Accept / Decline.
  - `message` → `ChatScreen` for `targetId`.
  - `new_event` → `EventDetailScreen` for `targetId`.
  - `story_*` → story viewer for `targetId`.

## FCM token lifecycle

- **On login:** `FcmService.init(uid)` requests permission, fetches token, writes `fcmTokens: arrayUnion([token])` to `users/{uid}`.
- **On token refresh:** `_messaging.onTokenRefresh` listener writes the new token.
- **On sign-out:** `FcmService.removeToken(uid)` in [`main.dart` line 266](../../lib/main.dart) → `fcmTokens: arrayRemove([token])` so no stale pushes target the device.

## Firestore writes / reads

| Path | Direction | Notes |
|------|-----------|-------|
| `notifications/{uid}/items/{nid}` | written by client / CF; read by `NotificationScreen` | per-recipient subcollection, no fan-out |
| `users/{uid}.fcmTokens` | written by `FcmService`; read by `sendPushOnNotificationCreate` | array of device tokens |
| `users/{actorUid}` | read by push CF to resolve display name | |

## Cloud Functions

- **[`sendPushOnNotificationCreate`](../../functions/src/notifications.ts)** — universal push fanout for notification doc creates.
- **[`onLikeCreate`](../../functions/src/likes.ts)**, **[`onCommentCreate`](../../functions/src/comments.ts)**, **[`onFollowCreate/Update/Delete`](../../functions/src/follows.ts)**, **[`onMessageCreate`](../../functions/src/messages.ts)**, **[`onEventCreate`](../../functions/src/events.ts)** — write notification docs (which then trigger the push fanout).

## Failure paths

- **No FCM token** (push permission denied, web without VAPID, iOS without APNS). `tokens.length === 0` → push CF returns silently. The notification doc is still written, so the in-app NotificationScreen still shows it.
- **iOS APNS race on first launch.** `FcmService.init` polls `getAPNSToken()` up to 10× with 500 ms between, then falls back to `onTokenRefresh` listener — token gets written later.
- **Notification doc write rejected by rules.** Client write fails → caller best-effort try/catch swallows; CF write may still succeed.
- **Push send error (invalid token).** `sendEachForMulticast` reports per-token failures. The function doesn't currently prune dead tokens from `fcmTokens` (would require iterating the response and writing `arrayRemove`), so dead tokens accumulate. A future cleanup function could batch these out.
- **Two duplicate notification docs for one like.** Recipient sees two list rows (read state independent) and gets two FCM pushes. Workaround: client deterministic id collapses on the recipient's view if you query for it specifically, but the list view shows both.
- **`new_event` cold-open with deleted event.** `_openEventDetailFromPush` does `events/{id}.get()`; on missing, pushes [`EventUnavailableScreen`](../../lib/src/features/screens/admin/admin_events_screen.dart) instead of the detail.

## Related files

- [`lib/main.dart`](../../lib/main.dart) — `_handleFcmEvent`, `_openEventDetailFromPush`, FCM init via `ref.listen<AsyncValue<User?>>`.
- [`lib/src/services/fcm_service.dart`](../../lib/src/services/fcm_service.dart)
- [`lib/src/services/notification_service.dart`](../../lib/src/services/notification_service.dart)
- [`lib/src/providers/notification_providers.dart`](../../lib/src/providers/notification_providers.dart)
- [`lib/src/features/screens/notification_screen.dart`](../../lib/src/features/screens/notification_screen.dart)
- [`functions/src/notifications.ts`](../../functions/src/notifications.ts)
- [`functions/src/likes.ts`](../../functions/src/likes.ts)
- [`functions/src/comments.ts`](../../functions/src/comments.ts)
- [`functions/src/follows.ts`](../../functions/src/follows.ts)
- [`functions/src/messages.ts`](../../functions/src/messages.ts)
- [`functions/src/events.ts`](../../functions/src/events.ts)
