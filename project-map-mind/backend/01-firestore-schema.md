# Firestore Schema

Every Cloud Firestore collection and sub-collection used by the COIL app. Fields listed are those actually written by client services in [`lib/src/services/*.dart`](../../lib/src/services) or by Cloud Functions in [`functions/src/*.ts`](../../functions/src). Where a field is touched but its semantics are inferred, it is flagged "use unclear".

Top-level collections at a glance:

| Path | Purpose | Writer |
| --- | --- | --- |
| `users/{uid}` | User profile, settings, FCM tokens | Client (self), admin functions |
| `posts/{postId}` | Feed posts, travel posts, Q&A topics | Client (author) |
| `stories/{storyId}` | 24h photo/video/text stories | Client (author) |
| `events/{eventId}` | Admin-published events | Client (admin/org_admin) |
| `eventChats/{eventId}` | Event-attached group chat | Client (admin/org_admin) |
| `eventRegistrations/{regId}` | Per-user request to join an event | Client (user submits, admin updates) |
| `chats/{chatId}` | 1:1 + multi-party direct chats | Client (any participant) |
| `feeds/{uid}/timeline/{postId}` | Server-fanned feed pointers | Cloud Function `onPostCreate` |
| `notifications/{uid}/items/{itemId}` | In-app notification inbox | Client + multiple Cloud Functions |
| `adminConfig/{docId}` | Feature flags / event-type list / profanity words | Admin client |
| `errorReports/{id}` | Crash + handled-error reports | Client `ErrorReportService` |
| `postReports/{id}`, `discussReports/{id}`, `userReports/{id}` | Moderation reports | Client (reporter) |
| `blacklist/{email}` | Deleted-account tombstones | Client (self-delete + admin) |
| `contactRequests/{id}` | Support / "become organization" threads | Client (user + admin) |

The catch-all rule at the bottom of [`firestore.rules`](../../firestore.rules) (lines 688-690) denies anything not listed below.

---

## Users domain

### `users/{uid}` — profile root

Created by the client on signup ([`auth_service.dart:171-209, 272-291, 330-349`](../../lib/src/services/auth_service.dart)). Doc id = Firebase Auth uid.

| Field | Type | Source / purpose |
| --- | --- | --- |
| `uid` | string | denormalized uid (== doc id) |
| `email` | string \| null | Firebase Auth email (backfilled in [`_ensureUserDoc`](../../lib/src/services/auth_service.dart) when missing) |
| `username` | string \| null | unique display handle |
| `usernameLower` | string | lower-cased for uniqueness lookup ([`user_service.dart:144-150`](../../lib/src/services/user_service.dart)) |
| `handle` | string \| null | secondary handle (use unclear, written as null at signup) |
| `bio` | string | free-text profile bio |
| `avatarUrl` | string \| null | Supabase Storage public URL |
| `coverUrl` | string \| null | cover photo URL |
| `gender` | string \| null | selected gender |
| `role` | enum string | `'user'` (default) / `'admin'` / `'org_admin'` ([`firestore.rules:19-33`](../../firestore.rules)) |
| `suspended` | bool | flipped by `adminSuspendUser` Cloud Function ([`functions/src/adminUsers.ts:166-196`](../../functions/src/adminUsers.ts)) |
| `suspendedAt` | Timestamp | only set while suspended |
| `suspendedBy` | string | admin uid that suspended |
| `deleted` | bool | tombstone set by `adminDeleteUser` / `selfDeleteAccount` |
| `deletedAt`, `deletedBy` | Timestamp / string | matching delete metadata |
| `isPrivate` | bool | gates follow approval flow |
| `appIntroSeen` | bool | onboarding flag |
| `followersCount`, `followingCount`, `postsCount` | int | denormalized counters, updated by [`follows.ts`](../../functions/src/follows.ts) and [`post_service.dart`](../../lib/src/services/post_service.dart) |
| `fcmTokens` | string[] | array of device tokens, written by [`fcm_service.dart:_saveToken`](../../lib/src/services/fcm_service.dart) |
| `createdAt` | Timestamp | server timestamp at signup |
| `eventNotifPrefs` | map `{mode, types[], countries[]}` | new-event notification filters; consumed by [`events.ts`](../../functions/src/events.ts) and [`admin_service.dart:_fanOutNewEventNotifications`](../../lib/src/services/admin_service.dart) |
| `blockedUsers` | string[] | uids this user has blocked ([`block_service.dart:21-23`](../../lib/src/services/block_service.dart)) |
| `lastContactRequestDay`, `lastContactRequestAt` | string / Timestamp | rate-limit lock for contact-us ([`contact_request_service.dart:266-281`](../../lib/src/services/contact_request_service.dart)) |
| `orgAdminGrantedAt`, `orgAdminRevokedAt` | Timestamp | set when promoted to / from `org_admin` |
| Profile personalization fields (e.g. profession, field, academicLevel, goals) | strings / lists | use unclear in this audit; populated from onboarding wizard against [`AdminConfig`](../../lib/src/services/admin_service.dart) option lists |

Read access: `allow read: if true` ([`firestore.rules:163`](../../firestore.rules)). Profile pages are publicly fetchable; the client filters private profiles.

#### Sub-collections under `users/{uid}`

| Sub-path | Doc id | Shape | Writer / purpose |
| --- | --- | --- | --- |
| `followers/{followerUid}` | follower's uid | `{uid, createdAt, status: 'pending'\|'active', acceptedAt?}` | client `FollowService.follow` ([`follow_service.dart:71-80`](../../lib/src/services/follow_service.dart)); Cloud Function `onFollowCreate/Update/Delete` adjusts counters and notifications ([`functions/src/follows.ts`](../../functions/src/follows.ts)) |
| `following/{followingUid}` | followed user's uid | mirror of above | same writer; the pair is always written atomically |
| `blockedUsers/{blockedUid}` | blocked uid | (legacy sub-collection — most blocks live in the `users.blockedUsers` array now). Empty docs created via batch in some paths |
| `reposts/{postId}` | post id | `{createdAt}` | [`post_service.dart:744-790`](../../lib/src/services/post_service.dart); paired with `posts/{postId}/reposts/{uid}` |
| `saved/{postId}` | post id | `{createdAt}` | [`post_service.dart:825-836`](../../lib/src/services/post_service.dart) |
| `savedTranslations/{translationId}` | auto | shape used by the saved-translations screen; details out of scope here |
| `visitors/{visitorUid}` | visitor uid | `{lastVisitedAt, visitCount}` | [`profile_visitor_service.dart:42-55`](../../lib/src/services/profile_visitor_service.dart). Only the owner / admin reads it |
| `stickerPacks/{packId}` | auto | `{name, ownerUid, stickerUrls: string[], createdAt}` | [`sticker_service.dart:99-198`](../../lib/src/services/sticker_service.dart) |

---

## Posts domain

### `posts/{postId}` — feed posts, travel posts, and Q&A topics

Created by [`PostService.createPost`](../../lib/src/services/post_service.dart) (line 54), `createQaPost` (228), `createQaPostFromPost` (277).

| Field | Type | Purpose |
| --- | --- | --- |
| `authorUid` | string | author uid (enforced by rules at create) |
| `authorUsername` | string | denormalized for feed rendering |
| `authorAvatar` | string \| null | denormalized avatar URL |
| `caption` | string | post body |
| `imageUrls` | string[] | Supabase Storage URLs |
| `videoUrls` | string[] | Supabase Storage URLs (optional) |
| `likesCount`, `commentsCount` | int | denormalized counters; bumped by Cloud Functions and clients |
| `isPrivate` | bool | restricts visibility client-side |
| `createdAt` | Timestamp | server timestamp |
| `postPlaceName`, `postPlaceCity` | string | travel-post place metadata |
| `postLocation` | `{lat, lng}` | optional pinned location |
| `postLocationExact` | bool | whether the pin is exact vs approximate |
| `placeSearchKey` | string | lower-cased haystack for client-side travel search |
| `postType` | `'qa'` \| absent | only set for Q&A topics |
| `discussKind` | `'question'` \| `'discussion'` | sub-flavor for Q&A |
| `sourcePostId` | string | when a Q&A topic was spun off a normal post |
| `discussTopicId` | string | reverse pointer set on the source post |

Updates: only the author or admin may edit content. Anyone signed-in may bump `commentsCount`/`likesCount` or set `discussTopicId` once ([`firestore.rules:282-290`](../../firestore.rules)).

#### Sub-collections under `posts/{postId}`

| Sub-path | Shape | Writer |
| --- | --- | --- |
| `likes/{uid}` | `{createdAt}` | [`PostService.toggleLike`](../../lib/src/services/post_service.dart) (line 689); Cloud Function `onLikeCreate` notifies author |
| `comments/{commentId}` | `{authorUid, authorUsername, authorAvatar, text, createdAt, parentCommentId?, replyToUsername?, helpfulCount, unhelpfulCount, likesCount, editedAt?}` | [`comment_service.dart:192-230`](../../lib/src/services/comment_service.dart); Cloud Function `onCommentCreate` increments `commentsCount` + writes notifications |
| `comments/{commentId}/likes/{uid}` | `{createdAt}` | [`comment_service.dart:484-535`](../../lib/src/services/comment_service.dart) |
| `comments/{commentId}/reactions/{uid}` | `{type: 'heart'\|'broken', createdAt}` | [`comment_service.dart:569-668`](../../lib/src/services/comment_service.dart); Cloud Function `onQaAnswerReactionWrite` writes notifications |
| `privateComments/{uid}/items/{commentId}` | comment shape plus `{profanityFiltered: true, senderOnly: true}` | sender-only moderated comments — only the author sees them ([`comment_service.dart:80-89`](../../lib/src/services/comment_service.dart)) |
| `reposts/{uid}` | `{createdAt}` | [`post_service.dart:744-790`](../../lib/src/services/post_service.dart) |

---

## Stories domain

### `stories/{storyId}`

Created by [`StoryService.createStory`](../../lib/src/services/story_service.dart) (line 151).

| Field | Type | Purpose |
| --- | --- | --- |
| `authorUid`, `authorUsername`, `authorAvatar` | denormalized | author identity |
| `imageUrl` | string | story image (may be empty for text or video-only) |
| `videoUrl`, `videoTrimStartMs`, `videoTrimEndMs` | string / int | video-story payload |
| `textContent`, `backgroundColor`, `textColor`, `textBorderStyle` | string / int / string | text-only story |
| `overlays` | array of `StoryTextOverlay.toJson()` maps | structured text overlays |
| `sharedPostId` | string \| null | when the story embeds a post |
| `createdAt`, `expiresAt` | Timestamp | now + 24h |
| `likesCount`, `commentsCount` | int | denormalized counters |

Reads are public (`allow read: if true`).

Sub-collections:
- `likes/{uid}` — `{createdAt}`. Client toggles via transaction.
- `comments/{commentId}` — `{authorUid, authorUsername, authorAvatar, text, createdAt, parentCommentId?, replyToUsername?}`.
- `comments/{commentId}/likes/{uid}` — `{createdAt}`.
- `viewers/{viewerUid}` — `{username, avatarUrl, viewedAt}`. Only the viewer themselves writes their own doc ([`firestore.rules:403-411`](../../firestore.rules)). Author + admin read.

---

## Events domain

### `events/{eventId}`

Created by [`AdminService.createEvent`](../../lib/src/services/admin_service.dart) (line 1109). Cloud Function `onEventCreate` runs the new-event fan-out.

| Field | Type | Source |
| --- | --- | --- |
| `title`, `subtitle`, `location`, `description`, `link`, `phone`, `email` | strings | admin-entered metadata |
| `imageUrls` | string[] | banner images |
| `deadline` | Timestamp | when the event closes |
| `eventType` | string | one of [`kEventTypes`](../../lib/src/services/admin_service.dart) |
| `country` | string | admin's chosen label (original casing) |
| `locationCountry` | string | lower-cased copy of `country`, used by event-notification fan-out matching |
| `locationCity` | string | lower-cased first segment of `location` (legacy) |
| `funds` | string | one of [`kEventFundingStatuses`](../../lib/src/services/admin_service.dart) |
| `geo` | `{lat, lng}` \| absent | event map pin |
| `createdAt` | Timestamp | server timestamp |
| `createdByUid` | string | required for `org_admin` rule check |
| `notifiedUserCount`, `notifiedAt` | int / Timestamp | audit stamp written by `onEventCreate` ([`functions/src/events.ts:116-119`](../../functions/src/events.ts)) |

Reads: public. Writes: full admin, or `org_admin` for events they themselves created ([`firestore.rules:420-427`](../../firestore.rules)).

Sub-collection `events/{eventId}/attendees/{uid}` — `{...attendee fields}`. Each user writes their own doc; rules at lines 429-432.

### `eventRegistrations/{eventId}_{uid}`

Per-user request to register for an event ([`event_registration_service.dart:78-103`](../../lib/src/services/event_registration_service.dart)).

| Field | Type |
| --- | --- |
| `eventId`, `eventTitle` | string |
| `userUid` | string |
| `name`, `email`, `phone`, `countryCode` | strings |
| `status` | `'pending'` \| `'approved'` \| `'rejected'` |
| `createdAt` | Timestamp |
| `reviewedAt`, `reviewedBy` | Timestamp / admin uid |

Doc id is deterministic so each user has at most one in-flight request per event. Users may create their own (status must start as `pending`); only admins may update / delete ([`firestore.rules:438-457`](../../firestore.rules)).

### `eventChats/{eventId}`

The group chat attached to an event ([`event_chat_service.dart`](../../lib/src/services/event_chat_service.dart)).

| Field | Type | Purpose |
| --- | --- | --- |
| `eventTitle` | string | denormalized title for inbox tile |
| `adminUid` | string | event creator (also the chat admin) |
| `lastMessage`, `lastMessageSenderUid`, `lastTime` | string / string / Timestamp | inbox-tile summary |
| `mutedFor` | string[] | uids who muted push for this chat |

Sub-collections:
- `members/{uid}` — `{uid, name, joinedAt, addedByAdmin?, lastSeenAt?}`. Admin writes via `addMember`; user removes themselves via `leaveGroup`. The `members` collection-group query (with composite index on `uid, joinedAt`) drives the "my event chats" tab.
- `messages/{messageId}` — `{senderUid, text, imageUrl?, createdAt}`. Only the admin (rules) sends; members read.
- `messages/{messageId}/reactions/{reactorUid}` — `{emoji, uid, createdAt}` ([`reaction_service.dart`](../../lib/src/services/reaction_service.dart)).
- `polls/{pollId}` — `{question, options[], createdByUid, createdAt, visibility, closed}` ([`poll_service.dart`](../../lib/src/services/poll_service.dart)).
- `polls/{pollId}/votes/{voterUid}` — `{optionIndex, createdAt}`.

---

## Chats domain

### `chats/{chatId}` — 1:1 and multi-party direct chats

For 1:1 chats the doc id is the deterministic `{minUid}_{maxUid}` ([`chat_service.dart:518-521`](../../lib/src/services/chat_service.dart)). Group chats get an auto id (`createGroup`, line 1040).

| Field | Type | Purpose |
| --- | --- | --- |
| `participants` | string[] | uids in the chat |
| `kind` | `'group'` \| absent | absent => 1:1 |
| `groupName`, `groupAvatarUrl`, `adminUid` | strings | group-only fields |
| `userData` | map\<uid, {username, avatarUrl}\> | denormalized per-participant display info |
| `lastMessage`, `lastMessageSenderUid`, `lastTime` | string / string / Timestamp | inbox tile summary, also bumped by `onMessageCreate` Cloud Function |
| `unread` | map\<uid, int\> | per-participant unread counters |
| `lastSeenAt` | map\<uid, Timestamp\> | last time each participant opened the chat |
| `acceptedBy` | string[] | uids who have accepted the chat (drives Requests vs. All tabs) |
| `mutedFor` | string[] | uids who muted push |
| `autoDeleteSeconds` | int \| absent | auto-purge threshold consumed by a (planned) scheduled job |
| `createdAt` | Timestamp | server timestamp |

Sub-collections under `chats/{chatId}`:

- `messages/{messageId}` — see below. Schema is intentionally wide because the bubble UI supports many message kinds.
  - `senderUid`, `receiverUid` (1:1 only)
  - `text`, `senderOnlyText` (for sender-only moderated)
  - `visibleToUids` (string[]), `visibility: 'sender_only'`, `profanityFiltered: true`, `moderation: {type, matched[]}`
  - `imageUrl`, `videoUrl`, `fileUrl`, `fileName`, `fileMimeType`, `fileSizeBytes`
  - `sharedPostId`
  - `voiceUrl`, `voiceDurationMs`, `voiceTranscript`
  - `stickerUrl`, `stickerPackId`
  - `replyToId`, `replyToText`, `replyToSenderUid`
  - `storyId`, `storyImageUrl` (reply-to-story)
  - `location: {lat, lng}`, `locationLabel`
  - `createdAt`, `seenBy: string[]`
  - `deletedForUids: string[]`, `deletedForEveryone: bool`, `deletedByUid`, `deletedAt`
  - `enc` (legacy ciphertext envelope — see [`chat_service.dart:419-420`](../../lib/src/services/chat_service.dart) for the "Message unavailable" fallback)
- `messages/{messageId}/reactions/{reactorUid}` — `{emoji, uid, createdAt}` ([`reaction_service.dart`](../../lib/src/services/reaction_service.dart)).
- `polls/{pollId}` and `polls/{pollId}/votes/{voterUid}` — same shape as in `eventChats` (the [`PollService`](../../lib/src/services/poll_service.dart) is parent-agnostic).

The Cloud Function [`onMessageCreate`](../../functions/src/messages.ts) bumps `unread`, sets `lastMessage`, and writes a `'message'` notification — but only when the message is NOT `sender_only` / profanity-filtered.

---

## Feeds (server-fanned timeline)

### `feeds/{uid}/timeline/{postId}`

Written exclusively by [`onPostCreate`](../../functions/src/posts.ts). Doc shape: `{postId, authorUid, createdAt}`. Each follower of a non-private post gets a pointer. Rules: only the owner may read; no client writes ([`firestore.rules:546-549`](../../firestore.rules)).

---

## Notifications

### `notifications/{uid}/items/{itemId}`

Per-user notification inbox. Doc ids are sometimes deterministic (e.g. `follow_{actorUid}`, `like_{actorUid}_{postId}`, `comment_{postId}_{commentId}_{actorUid}`, `new_event_{eventId}`, `qa_answer_{postId}_{commentId}_{actorUid}`) so client paths can upsert/remove without duplicates, and sometimes auto-generated ([`notification_service.dart`](../../lib/src/services/notification_service.dart)).

| Field | Type | Notes |
| --- | --- | --- |
| `type` | string | one of `follow`, `follow_request`, `follow_accept`, `like`, `comment`, `comment_like`, `reply`, `qa_answer`, `qa_reply`, `qa_answer_like`, `qa_answer_dislike`, `story_like`, `story_comment`, `story_reply`, `repost`, `message`, `new_event`, `event_invited`, `event_removed`, `event_approved`, `event_rejected`, `role_update` |
| `actorUid` | string | uid who triggered it; `''` for system notifications |
| `targetId` | string \| absent | post id / event id / chat id depending on type |
| `commentId` | string \| absent | when the notification points at a specific comment/answer |
| `title`, `subtitle` | string \| absent | used by system notifications (`new_event`, `role_update`) |
| `read` | bool | start false |
| `status` | string \| absent | e.g. `'accepted'` / `'rejected'` (only for follow_request) |
| `createdAt` | Timestamp | server timestamp |

Reads / writes: see [`firestore.rules:629-645`](../../firestore.rules). System notifications (`actorUid == ''`) may only be fanned out by admins (and org_admins for `new_event`).

---

## Reports & moderation

### `postReports/{reportId}`

Created by users via [`PostService.reportPost`](../../lib/src/services/post_service.dart) (line 133). Reviewed by admins ([`AdminService.streamPostReports`](../../lib/src/services/admin_service.dart) line 1022).

Fields (all required by the validator in [`firestore.rules:86-106`](../../firestore.rules)):
`postId, postAuthorUid, postAuthorUsername, postAuthorAvatar?, postCaption, reporterUid, reporterUsername, reason, details?, resolved (false on create), createdAt (== request.time), resolvedAt? (null on create)`.

Admin updates may only change `{resolved, resolvedAt}`.

### `discussReports/{reportId}`

Same shape as `postReports`, used for Q&A topics ([`post_service.dart:171-207`](../../lib/src/services/post_service.dart)).

### `userReports/{reportId}`

Profile reports ([`user_service.dart:93-129`](../../lib/src/services/user_service.dart)). Doc id pattern `{targetUid}_{reporterUid}`. Fields validated by [`firestore.rules:108-125`](../../firestore.rules):
`targetUid, targetUsername, targetAvatar?, reporterUid, reporterUsername, reason, details?, resolved, createdAt, resolvedAt`.

### `errorReports/{id}`

Crash and handled-error reports ([`error_report_service.dart:110-159`](../../lib/src/services/error_report_service.dart)).

Validated shape ([`firestore.rules:60-76`](../../firestore.rules)):
`message, stack, kind, context?, screen?, uid?, platform, appVersion, resolved (false), createdAt (== request.time)`.

Create is open to anyone (so boot-time crashes from unauthenticated users still log). Read / delete is admin-only; the only admin update permitted is flipping `resolved`.

### `blacklist/{email}`

Email-keyed tombstones written when a user is deleted. Read by signup to surface "this email was deleted" copy ([`admin_service.dart:819-825, 854-866`](../../lib/src/services/admin_service.dart)).

Fields: `{email, uid, deletedAt, selfDeleted?}`.

A user may read/write their own entry (rule line 156-160).

---

## Admin / app config

### `adminConfig/{docId}` (typically `adminConfig/app`)

Global flags + curated lists. Created/updated only by admins ([`firestore.rules:50-53`](../../firestore.rules)).

Fields written by [`AdminService.saveConfig`](../../lib/src/services/admin_service.dart) (line 692):

`storiesEnabled, repostsEnabled, translateEnabled, announcement, maintenanceMode, minAppVersion, contactEmail, iosAppStoreUrl, androidPlayStoreUrl, eventTypes[], profileProfessionOptions[], profileFieldOptions[], profileAcademicLevelOptions[], profileGoalOptions[], profanityWordsEn[]`.

`eventCountries` is intentionally NOT stored — the static list in code is the source of truth.

### `contactRequests/{requestId}`

Support / "become organization" threads ([`contact_request_service.dart`](../../lib/src/services/contact_request_service.dart)).

| Field | Type |
| --- | --- |
| `userUid`, `userEmail`, `userName` | strings (the requester) |
| `type` | `'message'` \| `'organization'` |
| `subject` | string (first 60 chars of opening message) |
| `status` | `'open'` \| `'answered'` \| `'promoted'` \| `'revoked'` |
| `createdAt`, `lastMessageAt` | Timestamps |
| `lastMessagePreview` | string (≤120 chars) |
| `unreadByUser`, `unreadByAdmin` | bool |

Sub-collection `contactRequests/{id}/messages/{messageId}` — `{senderUid, senderRole: 'user'|'admin', body, createdAt}`. Messages are immutable once created (rule line 684).

---

## Notes on legacy / inferred fields

- Some user-profile personalization fields (`profession`, `field`, `academicLevel`, `goals`) are referenced via `AdminConfig` option lists but the writes happen in onboarding screens this audit didn't open — their exact field names live in the onboarding widget files under `lib/src/features/`.
- `posts.commentsCount` and `posts.likesCount` are eventually-consistent counters maintained by a mix of Cloud Functions and clients. The Q&A UI prefers a live `count(comments)` ([`comment_service.dart:111-113`](../../lib/src/services/comment_service.dart)) to avoid drift.
- Legacy `enc` ciphertext envelopes appear on older chat messages but the encryption stack has been removed; clients render "Message unavailable".

---

## Related files

- [`firestore.rules`](../../firestore.rules) — authoritative list of collections (read for this doc)
- [`firestore.indexes.json`](../../firestore.indexes.json) — composite indexes
- [`functions/src/index.ts`](../../functions/src/index.ts) and siblings — Cloud Function writers
- [`lib/src/services/*.dart`](../../lib/src/services) — every Dart service that touches Firestore
