# Security Rules

A walkthrough of [`firestore.rules`](../../firestore.rules) (~692 lines), plus the smaller [`database.rules.json`](../../database.rules.json) (Realtime DB) and [`storage.rules`](../../storage.rules) files.

The catch-all `match /{document=**} { allow read, write: if false; }` at the bottom of `firestore.rules` means anything not explicitly matched is denied.

## Helper functions (top of file, lines 4-46)

| Helper | What it returns |
| --- | --- |
| `signedIn()` | `request.auth != null` |
| `isSelf(uid)` | true iff the request is authenticated as that uid |
| `canSeeContent(uid)` | true if the user is public, or it's their own content, or the viewer is an active follower. Currently only used in the rules history — kept around because get()-in-list rules can't filter list results (see comment lines 266-271) |
| `isAdmin()` | signed-in AND `users/{request.auth.uid}.role == 'admin'` |
| `isOrgAdmin()` | signed-in AND `users/{request.auth.uid}.role == 'org_admin'`. Only event-related rules accept it |
| `canManageNewEventNotification()` | true for org_admins on notifications of `type == 'new_event'` whose target event they themselves created. Used in the notifications delete rule |
| `isChatParticipant(chatId)` | viewer is in `chats/{chatId}.participants` |

## Validators (referenced by report-create rules)

- `isValidErrorReport()` (lines 60-76) — enforces field allowlist + size limits on `errorReports/*` creates: `message ≤2000`, `stack ≤8000`, `kind ≤40`, `context ≤1000`, `screen ≤200`, `uid ≤128`, `platform ≤40`, `appVersion ≤40`, `resolved == false`, `createdAt == request.time`.
- `isValidPostReport()` (lines 86-106) — same idea for `postReports/*` and `discussReports/*`: `reporterUid == request.auth.uid`, `reason ≤80`, `details ≤2000`, `postCaption ≤6000`, etc.
- `isValidUserProfileReport()` (lines 108-125) — same idea for `userReports/*`.

## Rules by collection

### `adminConfig/{docId}` (50-53)
- Read: any signed-in user (feature flags must be readable).
- Write: admin only.

### `errorReports/{reportId}` (77-84)
- Create: anyone (including not-yet-signed-in users), but the doc must pass `isValidErrorReport()`.
- Update: admin only, and only the `resolved` boolean may change.
- Read / delete: admin only.

### `postReports/{reportId}`, `discussReports/{reportId}` (127-141)
- Create: signed-in caller, doc must pass `isValidPostReport()`.
- Update: admin only, may only change `{resolved, resolvedAt}`.
- Read / delete: admin only.

### `userReports/{reportId}` (143-149)
- Create: signed-in caller, doc must pass `isValidUserProfileReport()`.
- Update / read / delete: admin only (update limited to `{resolved, resolvedAt}`).

### `blacklist/{email}` (155-160)
- Read / write: admin OR the user whose own email token matches the doc id. This lets a self-deleting user write their own tombstone and lets sign-in check whether their own email was deleted.

### `users/{uid}` (162-223)
- Read: open (`if true`). The client filters private profiles.
- Create / delete: self OR admin.
- Update: self OR admin.

Sub-collections under `users/{uid}`:

| Sub-path | Read | Create | Update | Delete |
| --- | --- | --- | --- | --- |
| `followers/{followerUid}` | signed-in | self of either side | profile owner | follower, owner, or admin |
| `following/{followingUid}` | signed-in | either side | either side | either side or admin |
| `blockedUsers/{blockedUid}` | signed-in | owner or admin | (denied) | owner or admin |
| `reposts/{postId}` | signed-in | owner | (denied) | owner or admin |
| `saved/{postId}` | owner or admin | owner | (denied) | owner or admin |
| `savedTranslations/{translationId}` | owner or admin | owner | (denied) | owner or admin |
| `visitors/{visitorUid}` | profile owner or admin | the visitor (≠ owner) | the visitor | profile owner, visitor, or admin |

### Collection-group rules (226-263)

These are needed for `collectionGroup` queries:

- `{path=**}/followers/{followerUid}` — admin can read (cascade-delete cleanup).
- `{path=**}/following/{followingUid}` — admin can read.
- `{path=**}/comments/{commentId}` — admin reads everything; any signed-in user reads their OWN comments. Used by the "Answers" tab on profiles.
- `{path=**}/likes/{likeUid}` — admin only.
- `{path=**}/reposts/{repostUid}` — admin only.
- `follows/{targetUid}/followers/{followerUid}` — alternate top-level layout used in one place; signed-in read, self create/delete.
- `posts/{postId}/comments/{commentId}/reactions/{uid}` — explicit `get, list` and create/update/delete for self (needed because snapshot listeners count as `list`).

### `posts/{postId}` (265-367)
- Read: any signed-in user. Privacy is enforced client-side because list queries can't filter via get() in rules.
- Create: author must equal the requester (`request.resource.data.authorUid == request.auth.uid`).
- Update: author, admin, OR any signed-in user limited to bumping `commentsCount`/`likesCount`, OR setting `discussTopicId` once.
- Delete: author or admin.

Sub-collections:

| Sub-path | Read | Create | Update | Delete |
| --- | --- | --- | --- | --- |
| `likes/{uid}` | signed-in | self | (n/a) | self or admin |
| `comments/{commentId}` | signed-in | author == requester | counters by anyone OR `{text, editedAt}` by author/admin | author or admin |
| `comments/{commentId}/likes/{uid}` | signed-in | self | (denied) | self or admin |
| `comments/{commentId}/reactions/{uid}` | signed-in | self or admin | self or admin | self or admin |
| `privateComments/{uid}` | self or admin | self or admin | (any) | self or admin |
| `privateComments/{uid}/items/{commentId}` | self or admin | self, author == requester | self, only `{text, editedAt}` and only if author == requester | self or admin |
| `reposts/{uid}` | signed-in | self | (denied) | self or admin |

### `stories/{storyId}` (369-413)
- Read: public (`if true`). Stories are intentionally browsable without auth — same applies to their likes/comments.
- Create: author == requester.
- Update: author, admin, OR any signed-in user limited to `{commentsCount, likesCount}`.
- Delete: author or admin.

Sub-collections:
- `likes/{uid}` — public read; self create; self/admin delete.
- `comments/{commentId}` — public read; author create; no updates; author/admin delete.
- `comments/{commentId}/likes/{uid}` — public read; self create; self/admin delete.
- `viewers/{viewerUid}` — read only by the viewer, story author, or admin; viewer creates/updates their own doc; admin deletes.

### `events/{eventId}` (415-433)
- Read: public.
- Create: admin OR (`org_admin` AND `request.resource.data.createdByUid == request.auth.uid`).
- Update / delete: admin OR (`org_admin` AND `resource.data.createdByUid == request.auth.uid`).
- `attendees/{uid}` — public read; self create/delete.

### `eventRegistrations/{regId}` (438-457)
- get: admin OR `resource.data.userUid == request.auth.uid` OR the doc id ends with `_{request.auth.uid}` (so a "not yet registered" get can still succeed and render the Register button).
- list: admin only.
- Create: signed-in requester, `userUid == auth.uid`, `status == 'pending'`.
- Update / delete: admin only.

### Members collection-group (464-466)
`{path=**}/members/{uid}` — any signed-in user can read their own member doc. Required for the "my event chats" `collectionGroup('members').where('uid', '==', uid)` query.

### `eventChats/{eventId}` (469-544)
- Read: admin OR member of the chat.
- Create / update: admin OR (`org_admin` AND `adminUid == request.auth.uid`).
- Delete: admin only.

Sub-collections:
- `members/{uid}` — members or admin read; admin writes; self or admin delete.
- `messages/{messageId}` — members or admin read; only admin sends (`senderUid == request.auth.uid`); admin delete; no updates.
- `messages/{messageId}/reactions/{reactorUid}` — members read; self create/update/delete only if also member or admin.
- `polls/{pollId}` — members read; admin creates with `createdByUid == request.auth.uid`; admin update/delete.
- `polls/{pollId}/votes/{voterUid}` — members read; self create/update/delete.

### `feeds/{uid}/timeline/{postId}` (546-549)
- Read: owner only.
- Write: denied (only Cloud Functions touch this).

### `chats/{chatId}` (551-627)
- get: participant or admin (also allowed when doc doesn't exist so the "does this chat exist" probe works).
- list: participant or admin.
- Create: requester must be in the new doc's `participants`.
- Update: any signed-in user who is currently in `participants` OR will be in `participants` after the write (lets a group admin add a member).
- Delete: admin only.

Messages sub-collection (lines 571-610):
- Read: chat participant or admin.
- Create: participant whose uid matches `senderUid`.
- Update: a participant may flip `seenBy`, append themselves to `deletedForUids` (with a precise size check to prevent stuffing other uids), or — only the original sender — set the trio `{deletedForEveryone, deletedByUid, deletedAt}` for delete-for-everyone.
- Delete: admin only.
- `reactions/{reactorUid}` — participant read; self create/update/delete only when also a participant.

Polls sub-collection (612-626):
- Read: participant.
- Create: participant with `createdByUid == request.auth.uid`.
- Update / delete: only the poll's creator.
- `votes/{voterUid}` — participant read; self create/update/delete only when participant.

### `notifications/{uid}/items/{itemId}` (629-645)
- get: self, admin, OR org_admin reading any item whose id starts with `new_event_` (so they can verify fan-out).
- list: self or admin.
- update: self.
- delete: self, admin, the original actor, OR an org_admin via `canManageNewEventNotification()`.
- create: signed-in writer whose `actorUid == request.auth.uid`, OR admin sending a system notification (`actorUid == ''`), OR org_admin sending a `new_event` system notification.

### `contactRequests/{requestId}` (652-686)
- get: admin OR `userUid == request.auth.uid`.
- list: any signed-in user (Firestore still enforces `get` per doc, so the client must query `where('userUid', '==', auth.uid)` or it errors).
- Create: signed-in writer with `userUid == auth.uid` and `type in ['message', 'organization']`.
- Update: admin OR the thread's user (lets either side flip unread / status).
- Delete: admin only.
- `messages/{messageId}` — admin or thread owner read; admin or thread owner create with `senderUid == request.auth.uid`; no updates or deletes.

---

## Realtime Database — [`database.rules.json`](../../database.rules.json)

Tiny file with two paths.

```jsonc
{
  "rules": {
    "presence": {
      "$uid": {
        ".read": "auth != null",
        ".write": "auth != null && auth.uid === $uid"
      }
    },
    "typing": {
      "$chatId": {
        "$uid": {
          ".read": "auth != null",
          ".write": "auth != null && auth.uid === $uid"
        }
      }
    }
  }
}
```

- `presence/{uid}` — any signed-in user reads anyone's presence; only the user themselves writes their own `{online, lastSeen}` ([`presence_service.dart`](../../lib/src/services/presence_service.dart)).
- `typing/{chatId}/{uid}` — any signed-in user reads typing indicators in any chat; only the typing user writes their own boolean ([`typing_service.dart`](../../lib/src/services/typing_service.dart)). Note: this is NOT scoped to chat participants — the chat-scope check happens at the Firestore-rules layer; anyone with the chatId can peek typing state.

## Storage — [`storage.rules`](../../storage.rules)

```rules
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /avatars/{uid}/{allPaths=**} {
      allow read: if true;
      allow write: if request.auth != null && request.auth.uid == uid;
    }
    match /posts/{uid}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

NOTE: the app does NOT use Firebase Storage for uploads — every upload goes through the Supabase edge function (see [`07-supabase.md`](07-supabase.md)). The rules above only matter for legacy bytes still hosted on the Firebase bucket (notably custom stickers, [`sticker_service.dart:120-127`](../../lib/src/services/sticker_service.dart), which uses `FirebaseStorage.instance` directly and writes to `users/{uid}/stickers/{packId}/...`). The legacy `posts/{uid}` path expects the user folder to be the first path segment — same convention the Supabase edge function uses for its bucket layout.

## Related files

- [`firestore.rules`](../../firestore.rules)
- [`database.rules.json`](../../database.rules.json)
- [`storage.rules`](../../storage.rules)
- [`firestore.indexes.json`](../../firestore.indexes.json) — composite indexes referenced by some of these queries
