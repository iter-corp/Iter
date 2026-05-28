# Cloud Functions

All functions live in [`functions/src/`](../../functions/src) and are re-exported as namespaces from [`functions/src/index.ts`](../../functions/src/index.ts). The compiled mirror under `functions/lib/*.js` exists only because Firebase deploys JS — keep editing TS. `admin.initializeApp()` runs once at the top of `index.ts`.

Functions are deployed on the Blaze plan; on Spark (no functions), many of the same effects are reproduced client-side (see notes per function).

## Inventory

| Export | Trigger | File | Domain |
| --- | --- | --- | --- |
| `adminUsers.adminSuspendUser` | onCall | [`adminUsers.ts`](../../functions/src/adminUsers.ts) | Admin moderation |
| `adminUsers.adminDeleteUser` | onCall | `adminUsers.ts` | Admin moderation |
| `adminUsers.selfDeleteAccount` | onCall | `adminUsers.ts` | Account deletion (App Store req) |
| `adminUsers.onUserDeletedCascadeCleanup` | onDocumentDeleted `users/{uid}` | `adminUsers.ts` | Cascade cleanup |
| `comments.onCommentCreate` | onDocumentCreated `posts/{postId}/comments/{commentId}` | [`comments.ts`](../../functions/src/comments.ts) | Notifications + counters |
| `comments.onQaAnswerReactionWrite` | onDocumentWritten `posts/{postId}/comments/{commentId}/reactions/{reactorUid}` | `comments.ts` | Q&A reaction notifications |
| `events.onEventCreate` | onDocumentCreated `events/{eventId}` | [`events.ts`](../../functions/src/events.ts) | new_event fan-out |
| `follows.onFollowCreate` | onDocumentCreated `users/{targetUid}/followers/{followerUid}` | [`follows.ts`](../../functions/src/follows.ts) | Counters + notifications |
| `follows.onFollowUpdate` | onDocumentUpdated same path | `follows.ts` | Pending↔active transitions |
| `follows.onFollowDelete` | onDocumentDeleted same path | `follows.ts` | Counter decrement |
| `likes.onLikeCreate` | onDocumentCreated `posts/{postId}/likes/{likerUid}` | [`likes.ts`](../../functions/src/likes.ts) | Like notification |
| `live.issueLiveToken` | onCall | [`live.ts`](../../functions/src/live.ts) | Agora RTC token |
| `live.onLiveStreamDelete` | onDocumentDeleted `liveStreams/{streamId}` | `live.ts` | Live stream cleanup marker |
| `messages.onMessageCreate` | onDocumentCreated `chats/{chatId}/messages/{messageId}` | [`messages.ts`](../../functions/src/messages.ts) | Chat summary + notifications |
| `notifications.sendPushOnNotificationCreate` | onDocumentCreated `notifications/{uid}/items/{notificationId}` | [`notifications.ts`](../../functions/src/notifications.ts) | FCM dispatch |
| `posts.onPostCreate` | onDocumentCreated `posts/{postId}` | [`posts.ts`](../../functions/src/posts.ts) | Feed fan-out |
| `translate.translateText` | onCall (with Secret `GEMINI_API_KEY`) | [`translate.ts`](../../functions/src/translate.ts) | Gemini translation |

The client only invokes the **onCall** functions directly via `cloud_functions`. Every other function is fired by Firestore triggers when the client writes a document.

## Client → callable map

`cloud_functions` is imported in [`lib/main.dart:3`](../../lib/main.dart) and only used to wire up the emulator at [`main.dart:95`](../../lib/main.dart). The repo has **no production `FirebaseFunctions.instance.httpsCallable(...)` invocations** at the time of writing — search yields only the emulator setup.

That means the four onCall functions (`adminSuspendUser`, `adminDeleteUser`, `selfDeleteAccount`, `issueLiveToken`, `translateText`) are wired in code but no client service is calling them yet. Their work is currently being done from the client itself:

- Translation: [`TranslateService`](../../lib/src/services/translate_service.dart) calls Gemini / Azure / MyMemory / Langbly directly with API keys from `.env`. The Cloud Function exists as a server-side fallback that keeps the key off the device.
- User delete: [`AdminService.deleteUser`](../../lib/src/services/admin_service.dart) and `selfDeleteCurrentUser` cascade-delete from the client.
- Live tokens: not wired into any service in this snapshot.

When the project graduates to Blaze, swap the client-side translation and delete paths for `httpsCallable('translateText')`, `httpsCallable('adminDeleteUser')`, etc. The Firestore triggers below already run regardless.

---

## Function details

### Notifications domain

#### `notifications.sendPushOnNotificationCreate`

- **Trigger:** `onDocumentCreated('notifications/{uid}/items/{notificationId}')`
- **Reads:** `users/{uid}.fcmTokens`, `users/{actorUid}.username`
- **Writes:** sends FCM via `admin.messaging().sendEachForMulticast`. Does NOT write Firestore.
- **What it does:** For every new notification doc, looks up the recipient's stored FCM tokens and the actor's username, then sends a push with a per-type title/body (see the switch in [`notifications.ts:29-75`](../../functions/src/notifications.ts)). The push payload carries `{type, actorUid, targetId}` so the client can deep-link.

#### `comments.onCommentCreate`

- **Trigger:** `onDocumentCreated('posts/{postId}/comments/{commentId}')`
- **Reads:** parent post doc, parent comment doc (for replies).
- **Writes:** increments `posts/{postId}.commentsCount`; writes one `notifications/{recipient}/items/{deterministic id}` doc.
- **Behavior:**
  - Regular post → notify post author with `type: 'comment'`.
  - Q&A topic, top-level → `type: 'qa_answer'`, deterministic id `qa_answer_{postId}_{commentId}_{actorUid}`.
  - Q&A topic, reply → `type: 'qa_reply'`, deterministic id `qa_reply_{postId}_{commentId}_{actorUid}`.
- Skips self-notifications.

The client-side `addComment` ([`comment_service.dart`](../../lib/src/services/comment_service.dart)) also writes the same deterministic notification docs as a Spark-plan fallback. Both are idempotent.

#### `comments.onQaAnswerReactionWrite`

- **Trigger:** `onDocumentWritten('posts/{postId}/comments/{commentId}/reactions/{reactorUid}')`
- **Reads:** the post (to confirm `postType == 'qa'`) and the comment (for the author).
- **Writes:** Deletes any old `qa_answer_like` / `qa_answer_dislike` notification, then writes a fresh one if the new reaction is `heart` or `broken`.
- **Skips:** reactor == comment author; non-Q&A posts.

### Follows domain

#### `follows.onFollowCreate` / `onFollowUpdate` / `onFollowDelete`

Path: `users/{targetUid}/followers/{followerUid}`.

| Function | Effect |
| --- | --- |
| `onFollowCreate` | If `status != 'pending'`: increments `followersCount` on target and `followingCount` on follower. Always writes a `follow` or `follow_request` notification with deterministic id `follow_{followerUid}` / `follow_request_{followerUid}`. |
| `onFollowUpdate` | Detects pending → active (counters +1, delete request notification) and active → pending (counters −1, recreate request notification). Skips no-ops. |
| `onFollowDelete` | If `status != 'pending'`: decrements counters. Deletes the matching notification doc. |

### Likes domain

#### `likes.onLikeCreate`

- **Trigger:** `onDocumentCreated('posts/{postId}/likes/{likerUid}')`
- **Reads:** the post (for author uid).
- **Writes:** an auto-id notification of `type: 'like'` for the post author. Skips self-like.

(The like counter itself is bumped in a transaction by the client, [`post_service.dart:689-731`](../../lib/src/services/post_service.dart).)

### Posts domain

#### `posts.onPostCreate`

- **Trigger:** `onDocumentCreated('posts/{postId}')`
- **Reads:** the post; `users/{authorUid}/followers`.
- **Writes:** one pointer per recipient at `feeds/{uid}/timeline/{postId}` with `{postId, authorUid, createdAt}`. Private posts only fan out to the author; public posts fan out to every follower. Batches at 450 writes (Firestore cap is 500).

### Events domain

#### `events.onEventCreate`

- **Trigger:** `onDocumentCreated('events/{eventId}')`
- **Reads:** every doc in `users` (TODO at [`events.ts:50-63`](../../functions/src/events.ts) notes this won't scale).
- **Writes:** one `notifications/{uid}/items/new_event_{eventId}` doc per matching user; updates the event doc itself with `{notifiedUserCount, notifiedAt}`.
- **Matching logic:** A user receives `new_event` if `suspended != true` AND `eventNotifPrefs.mode != 'off'` AND `(prefs.types empty || event.eventType in prefs.types)` AND `(prefs.countries empty || event.locationCountry in prefs.countries)`. The lower-cased `locationCountry` is what the event doc stores.
- The downstream push is handled by `sendPushOnNotificationCreate`.

The client mirrors this exact logic in [`AdminService._fanOutNewEventNotifications`](../../lib/src/services/admin_service.dart) (line 1177) so events still notify on Spark. The deterministic doc id keeps both writers idempotent.

### Messages domain

#### `messages.onMessageCreate`

- **Trigger:** `onDocumentCreated('chats/{chatId}/messages/{messageId}')`
- **Reads:** chat doc (when `receiverUid` is missing).
- **Writes:** updates the chat doc — `lastMessage`, `lastMessageSenderUid`, `lastTime`, increments `unread.{receiverUid}`, resets `unread.{senderUid}`, adds sender to `acceptedBy`. Also creates a `notifications/{receiverUid}/items/{auto-id}` doc of `type: 'message'`.
- **Skip cases:** `visibility == 'sender_only'`, `profanityFiltered == true`, or `visibleToUids` lists only the sender. This guarantees moderated messages never reach the recipient as a push or unread bump.

The client `sendMessage` ([`chat_service.dart:589`](../../lib/src/services/chat_service.dart)) already writes the same chat-summary updates atomically with the message, so the function's chat-doc writes are mostly redundant but idempotent (the deterministic merge is safe).

### Admin moderation

#### `adminUsers.adminSuspendUser`

- **Trigger:** onCall.
- **Auth:** caller must have `role: 'admin'`. Cannot self-suspend.
- **Input:** `{uid: string, suspended: bool}`.
- **Writes:** `users/{uid}.suspended/suspendedAt/suspendedBy`; also `admin.auth().updateUser(uid, {disabled: suspended})`.
- **Returns:** `{uid, suspended}`.

#### `adminUsers.adminDeleteUser`

- **Trigger:** onCall.
- **Auth:** admin role required; cannot delete self.
- **Effect:** Calls the shared `cleanupUserData` helper:
  - Deletes every doc in `posts` where `authorUid == target` (via `db.recursiveDelete`, so sub-collections go too).
  - Deletes every doc in the `comments` collection-group authored by target, fixing `commentsCount` on each affected post.
  - Deletes every doc in `stories` and `liveStreams` matching `authorUid` / `hostUid`.
  - Recursively deletes `notifications/{target}` and `feeds/{target}`.
- Marks `users/{target}` with `{deleted: true, deletedAt, deletedBy}` (does not actually delete the doc — the tombstone is needed for the sign-in flow to recognise the account as gone).
- Calls `admin.auth().deleteUser(target)`, swallowing `auth/user-not-found`.
- **Returns:** `{uid, deletedPosts, deletedComments, deletedStories, deletedLiveStreams}`.

#### `adminUsers.selfDeleteAccount`

- **Trigger:** onCall.
- **Auth:** any signed-in user; the caller IS the target.
- **Effect:** same `cleanupUserData` then mark the user doc deleted and `auth.deleteUser`.
- Exists to satisfy the App Store self-delete requirement. Currently the client also has a Spark-fallback ([`AdminService.selfDeleteCurrentUser`](../../lib/src/services/admin_service.dart) line 847) that does the same cascade plus an email-rename trick.

#### `adminUsers.onUserDeletedCascadeCleanup`

- **Trigger:** `onDocumentDeleted('users/{uid}')`.
- **Effect:** If a user doc disappears (e.g. an admin deletes the doc directly), run `cleanupUserData` and best-effort delete the Auth user. Acts as a safety net for paths that bypass the callable.

### Live streams

#### `live.issueLiveToken`

- **Trigger:** onCall.
- **Input:** `{channelName: string, role: 'host'|'audience'}`.
- **Effect:** Uses `AGORA_APP_ID` / `AGORA_APP_CERTIFICATE` env vars to mint an Agora RTC token via `RtcTokenBuilder.buildTokenWithUid`. Expires in 1 h.
- **Returns:** `{channelName, role, appId, token, expiresAt}`. Returns `token: null` when the env vars are unset (lets the client fall back to App-ID-only mode).

#### `live.onLiveStreamDelete`

- **Trigger:** `onDocumentDeleted('liveStreams/{streamId}')`.
- **Effect:** Writes a marker doc at `liveStreamCleanup/{streamId}` with `{cleanedAt}`. Intended as a hook for future analytics / chat-replay cleanup.

### Translation

#### `translate.translateText`

- **Trigger:** onCall.
- **Secrets:** `GEMINI_API_KEY` (defined with `defineSecret` so it's only readable inside the function).
- **Input:** `{text: string, sourceLang: string, targetLang: string}`.
- **Output:** `{translatedText, sourceLang, targetLang}`.
- **Behavior:** Sends a single Gemini `gemini-2.5-flash` request with `temperature: 0.2` and a strict "return only the translated text" prompt. Maps upstream HTTP codes to `HttpsError`s (`unavailable`, `resource-exhausted`, `internal`).
- **Currently unused by the client.** The Dart [`TranslateService`](../../lib/src/services/translate_service.dart) does its own multi-provider routing with API keys baked into `.env`.

---

## Notes for future maintainers

- Both clients and Cloud Functions write to many of the same notification ids on purpose. Deterministic ids (`like_{actorUid}_{postId}`, `follow_{actorUid}`, etc.) keep the two writers idempotent. If you delete one writer, audit the other for missing edge cases first.
- Several functions iterate the entire `users` collection (event fan-out, admin delete cleanup). Both have TODOs for scale; on Blaze you'd want a queue or a country-indexed query.
- `db.recursiveDelete` (admin-only API) is used in `adminUsers.ts` to nuke `posts/{id}/...`, `notifications/{uid}/...`, and `feeds/{uid}/...`. It is NOT available to the client.

## Related files

- [`functions/src/index.ts`](../../functions/src/index.ts), [`adminUsers.ts`](../../functions/src/adminUsers.ts), [`comments.ts`](../../functions/src/comments.ts), [`events.ts`](../../functions/src/events.ts), [`follows.ts`](../../functions/src/follows.ts), [`likes.ts`](../../functions/src/likes.ts), [`live.ts`](../../functions/src/live.ts), [`messages.ts`](../../functions/src/messages.ts), [`notifications.ts`](../../functions/src/notifications.ts), [`posts.ts`](../../functions/src/posts.ts), [`translate.ts`](../../functions/src/translate.ts)
- [`functions/lib/*.js`](../../functions/lib) — compiled JS (do not edit by hand)
- [`lib/src/services/admin_service.dart`](../../lib/src/services/admin_service.dart) — client mirrors of the moderation/event-fanout pipelines
- [`lib/main.dart`](../../lib/main.dart) — `FirebaseFunctions.instance.useFunctionsEmulator` wiring
