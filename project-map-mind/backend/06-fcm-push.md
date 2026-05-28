# Firebase Cloud Messaging (FCM)

How push notifications flow end-to-end: client token registration → Firestore notification doc → Cloud Function FCM dispatch → client tap handler → deep-link route.

## Client setup — [`fcm_service.dart`](../../lib/src/services/fcm_service.dart)

`FcmService.init(uid)` is called once per sign-in from [`main.dart:259-260`](../../lib/main.dart). It:

1. Registers `_onBackgroundMessage` as the background handler (top-level no-op; the OS itself shows the notification payload).
2. Requests OS permission (`alert/badge/sound`) and `setForegroundNotificationPresentationOptions(alert/badge/sound)`.
3. On iOS/macOS, polls `getAPNSToken()` up to 10 times (500 ms each) before calling `getToken()` — the FCM token is unavailable until APNS finishes. If APNS never settles, the service registers an `onTokenRefresh` listener and waits.
4. Calls `_saveToken(uid, token)` which writes `users/{uid}.fcmTokens` with `FieldValue.arrayUnion([token])`.
5. Subscribes to `onMessage`, `onMessageOpenedApp`, and `getInitialMessage()`. All three feed a single `FcmMessageEvent` broadcast stream that the app listens to in [`main.dart:161`](../../lib/main.dart).

`FcmService.removeToken(uid)` is invoked on sign-out — it calls `getToken()` again and arrays-removes that exact value from `fcmTokens` so this device stops receiving pushes for the signed-out account.

### Token storage shape

```
users/{uid}.fcmTokens: string[]
```

Tokens are never overwritten — `arrayUnion` deduplicates, `arrayRemove` deletes one. Multiple devices belonging to the same user all coexist in the array.

## Server-side dispatch — [`notifications.ts`](../../functions/src/notifications.ts)

Function `sendPushOnNotificationCreate` fires on `notifications/{uid}/items/{notificationId}` create. It:

1. Reads the recipient's `users/{uid}` doc and filters non-empty tokens.
2. Resolves the actor's username (`users/{actorUid}.username`) for the push body.
3. Builds a per-type title/body via a switch (lines 29-75):

| `type` | Title | Body |
| --- | --- | --- |
| `follow` | "New follower" | "{actor} started following you" |
| `like` | "New like" | "{actor} liked your post" |
| `qa_answer_like` | "New like" | "{actor} liked your answer" |
| `qa_answer_dislike` | "New reaction" | "{actor} disliked your answer" |
| `comment` | "New comment" | "{actor} commented on your post" |
| `qa_answer` | "New answer" | "{actor} answered your question" |
| `qa_reply` / `reply` | "New reply" | "{actor} replied to you" |
| `message` | "New message" | "{actor} sent you a message" |
| `new_event` | "New event" | `eventTitle — location` (data carries `title`/`subtitle` on the notification doc) |
| (default) | "COIL" | "{actor} interacted with you" |

4. Calls `admin.messaging().sendEachForMulticast({ tokens, notification, data })` where the data payload is:

```jsonc
{
  "type": "<notification type>",
  "actorUid": "<uid or ''>",
  "targetId": "<post id / event id / chat id>"
}
```

Note: not all notification types are mapped — e.g. `comment_like`, `story_like`, `story_comment`, `story_reply`, `repost`, `role_update`, the `event_*` types. Those fall through to the default copy.

## Client tap handling — `_handleFcmEvent` in [`lib/main.dart:200-214`](../../lib/main.dart)

```dart
void _handleFcmEvent(FcmMessageEvent event) {
  if (!event.openedApp || !mounted) return;
  final messageId = event.message.messageId;
  if (messageId != null && !_handledFcmMessageIds.add(messageId)) {
    return;            // dedupe — same message can fire onOpenedApp + getInitialMessage
  }
  final data = event.message.data;
  final type = data['type']?.trim();
  final targetId = data['targetId']?.trim();
  if (type == 'new_event' && targetId != null && targetId.isNotEmpty) {
    unawaited(_openEventDetailFromPush(targetId));
  }
}
```

Only `new_event` is currently deep-linked — `_openEventDetailFromPush` fetches `events/{eventId}` and either pushes `EventDetailScreen` or `EventUnavailableScreen` if the event was deleted. Other notification types do nothing on tap besides bringing the app to the foreground; users have to navigate to the relevant screen manually.

`openedApp` is true for both `onMessageOpenedApp` (tapped while backgrounded) and the synthetic `FcmMessageEvent` constructed from `getInitialMessage()` (tapped while terminated). `onMessage` (foreground) emits `openedApp: false` so the handler skips it.

## Suppression

- **Muted chats:** chat docs carry `mutedFor: string[]` ([`chat_service.dart:1202-1211`](../../lib/src/services/chat_service.dart)). The current Cloud Function dispatcher does NOT consult `mutedFor` — push goes to every token. The mute is enforced at the notification-doc level: `onMessageCreate` always writes the notification regardless. (The comment "the backend FCM dispatcher is expected to skip push delivery when the recipient appears in mutedFor" is aspirational.)
- **Profanity-filtered messages:** `onMessageCreate` returns early before writing a notification when `visibility == 'sender_only'` or `profanityFiltered == true` ([`messages.ts:18-23`](../../functions/src/messages.ts)), so no push fires.
- **Suspended users:** `onEventCreate` skips suspended users so they never receive a `new_event` notification ([`events.ts:82-83`](../../functions/src/events.ts)).

## Token cleanup

- **Sign-out:** `FcmService.removeToken(uid)` removes the current device's token.
- **Stale tokens:** the dispatcher does NOT prune dead tokens from `fcmTokens` after `sendEachForMulticast` returns errors. A future pass should reap tokens whose result is `messaging/registration-token-not-registered`.

## Web caveats

`FcmService.init` skips token persistence on web (`kIsWeb`) because the web SDK additionally requires a VAPID key, which is not configured in this snapshot. The event-listener setup still runs, so web users see no push notifications but the in-app notification inbox works fine.

## Related files

- [`lib/src/services/fcm_service.dart`](../../lib/src/services/fcm_service.dart) — token storage + event stream
- [`lib/main.dart`](../../lib/main.dart) — `_handleFcmEvent` and event-stream wiring (lines 161, 200-250, 254-272)
- [`functions/src/notifications.ts`](../../functions/src/notifications.ts) — server-side FCM dispatch
- [`functions/src/messages.ts`](../../functions/src/messages.ts), [`events.ts`](../../functions/src/events.ts), [`comments.ts`](../../functions/src/comments.ts), [`follows.ts`](../../functions/src/follows.ts), [`likes.ts`](../../functions/src/likes.ts) — notification doc creators that trigger the dispatch
- [`lib/src/services/notification_service.dart`](../../lib/src/services/notification_service.dart) — client-side helpers that create the same notification docs
