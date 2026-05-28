# Firebase & Supabase Setup

## Firebase project

- **Project ID:** `coil-50528` ([`.firebaserc`](../../.firebaserc), [`lib/firebase_options.dart:53,62,71`](../../lib/firebase_options.dart)).
- **Messaging sender ID:** `751233585713`.
- **Storage bucket:** `coil-50528.firebasestorage.app`.
- **Realtime Database URL:** `https://coil-50528-default-rtdb.asia-southeast1.firebasedatabase.app` (Singapore region — [`lib/firebase_options.dart:64,75`](../../lib/firebase_options.dart)).
- **Web auth domain:** `coil-50528.firebaseapp.com`.
- **iOS bundle id:** `com.iter.ai` ([`lib/firebase_options.dart:73`](../../lib/firebase_options.dart)).
- **iOS Google client ID:** `751233585713-tgffet0qbu9em9mlhsbh84jiqrh24a8o.apps.googleusercontent.com`.
- **Configured platforms** (`DefaultFirebaseOptions`): `web`, `android`, `ios`. `macOS`, `windows`, `linux` explicitly throw `UnsupportedError`.

## Firebase services in use

From [`firebase.json`](../../firebase.json) and feature inspection:

| Service | Enabled | Evidence |
|---|---|---|
| Authentication | yes | `firebase_auth ^5.7.0`, [`lib/src/services/auth_service.dart`](../../lib/src/services/auth_service.dart) |
| Cloud Firestore | yes | rules at [`firestore.rules`](../../firestore.rules), indexes at [`firestore.indexes.json`](../../firestore.indexes.json) |
| Realtime Database | yes | rules at [`database.rules.json`](../../database.rules.json), URL in firebase_options |
| Cloud Storage | yes | rules at [`storage.rules`](../../storage.rules) |
| Cloud Functions | yes | `functions/` source declared in [`firebase.json:12-17`](../../firebase.json) |
| Cloud Messaging (FCM) | yes | [`lib/src/services/fcm_service.dart`](../../lib/src/services/fcm_service.dart) + `UIBackgroundModes: remote-notification` in [`ios/Runner/Info.plist:73-76`](../../ios/Runner/Info.plist) |
| App Check | not documented; check [`firebase.json`](../../firebase.json) if needed |
| Crashlytics | not configured. The custom `ErrorReportService` writes to the `errorReports` Firestore collection instead ([`lib/src/services/error_report_service.dart`](../../lib/src/services/error_report_service.dart)). |
| Analytics | not documented; no `firebase_analytics` dep in [`pubspec.yaml`](../../pubspec.yaml). |
| Remote Config | not used directly; the `adminConfig` Firestore doc plays a similar role for `minAppVersion` etc. ([`firestore.rules:50-53`](../../firestore.rules)). |

## Authentication providers

From [`lib/src/services/auth_service.dart`](../../lib/src/services/auth_service.dart):

- **Email + password** (with email verification via OTP screen — see `requiresEmailVerification` getter and [`lib/src/features/screens/auth/otp_screen.dart`](../../lib/src/features/screens/auth/otp_screen.dart)).
- **Google Sign-In** (`google_sign_in ^6.2.2`, URL scheme registered in [`ios/Runner/Info.plist:69`](../../ios/Runner/Info.plist)).
- **Apple Sign-In** (`sign_in_with_apple ^7.0.1`, nonce hashed with `crypto`).
- **Forgot-password** flow uses Firebase Auth password reset email ([`lib/src/features/screens/auth/forgot_password_screen.dart`](../../lib/src/features/screens/auth/forgot_password_screen.dart)).

## Cloud Functions (Node 20, TypeScript)

[`functions/src/index.ts:16-27`](../../functions/src/index.ts) exports these modules:

| Module | File | Role |
|---|---|---|
| `adminUsers` | [`functions/src/adminUsers.ts`](../../functions/src/adminUsers.ts) | Admin user moderation (delete user cascade etc.) |
| `comments` | [`functions/src/comments.ts`](../../functions/src/comments.ts) | Comment fan-out / counters |
| `events` | [`functions/src/events.ts`](../../functions/src/events.ts) | Event lifecycle / FCM fan-out for `new_event` notifications |
| `follows` | [`functions/src/follows.ts`](../../functions/src/follows.ts) | Follow / follower bookkeeping |
| `likes` | [`functions/src/likes.ts`](../../functions/src/likes.ts) | Like counter triggers |
| `live` | [`functions/src/live.ts`](../../functions/src/live.ts) | Issues Agora RTC tokens via `agora-access-token` |
| `messages` | [`functions/src/messages.ts`](../../functions/src/messages.ts) | DM/chat triggers (unread counters, push) |
| `notifications` | [`functions/src/notifications.ts`](../../functions/src/notifications.ts) | Push fan-out from `notifications/{uid}/items` |
| `posts` | [`functions/src/posts.ts`](../../functions/src/posts.ts) | Post triggers (feed fan-out, deletions) |
| `translate` | [`functions/src/translate.ts`](../../functions/src/translate.ts) | Google Cloud Translate proxy (uses `@google-cloud/translate`) |

`firebase-admin` is initialized once in `index.ts`. The Flutter client invokes these via `cloud_functions ^5.1.5` (callable) and `firebase_messaging` reacts to push payloads.

Maintenance scripts (Node, not deployed) live in `functions/scripts/`:

- `seed:profanity` — seeds the profanity word list.
- `backfill:message-visibility` — backfills `visibleToUids` on legacy messages.

## Firestore data model (collections)

Derived from [`firestore.rules`](../../firestore.rules) match paths:

- `users/{uid}` — profile docs. Subcollections: `followers`, `following`, `blockedUsers`, `reposts`, `saved`, `savedTranslations`, `visitors`.
- `posts/{postId}` — feed posts (regular + Q&A "question" posts). Subcollections: `likes`, `comments` (which has `likes` and `reactions` per comment), `privateComments/{uid}/items`, `reposts`.
- `stories/{storyId}` — story items. Subcollections: `likes`, `comments` (with nested `likes`), `viewers`.
- `events/{eventId}` — event entries (+ `attendees` subcollection).
- `eventRegistrations/{eventId}_{uid}` — deterministic-id registration requests, status `pending`/approved/rejected.
- `eventChats/{eventId}` — group chat for an event. Subcollections: `members`, `messages` (+ per-message `reactions`), `polls` (+ per-poll `votes`).
- `chats/{chatId}` — 1:1 / group DM threads. Subcollections: `messages` (+ `reactions`), `polls` (+ `votes`).
- `feeds/{uid}/timeline/{postId}` — per-user fan-out timeline (server-written only; client read-only).
- `notifications/{uid}/items/{itemId}` — inbox notifications (`like`, `comment`, `follow`, `new_event`, `role_update`, etc.).
- `contactRequests/{requestId}` — user ↔ admin support threads. Subcollection: `messages`.
- `adminConfig/{docId}` — public app-wide config (feature flags, `minAppVersion`, announcements).
- `errorReports/{reportId}` — open-create crash reports with strict shape validation.
- `postReports`, `discussReports`, `userReports` — moderation reports (create by any signed-in user, admin-only read/resolve).
- `blacklist/{email}` — tombstone for deleted accounts; readable by admins and the owning email.
- `follows/{targetUid}/followers/{followerUid}` — legacy aux follower collection (rules still present at lines 252-255).

## Firestore composite indexes

[`firestore.indexes.json`](../../firestore.indexes.json):

| Collection (group / scope) | Fields | Used by |
|---|---|---|
| `posts` (collection) | `authorUid` ASC, `createdAt` DESC | Profile timeline + admin per-user post lists |
| `posts` (collection) | `isPrivate` ASC, `createdAt` DESC | Public feed query |
| `eventRegistrations` (collection) | `status` ASC, `createdAt` DESC | Admin "pending registrations" list |
| `members` (collection group) | `uid` ASC, `joinedAt` DESC | "Which event chats am I in?" lookup |
| `items` (collection) | `read` ASC, `createdAt` DESC | Notifications unread query |
| `messages` (collection) | `visibleToUids` array-contains, `createdAt` ASC | Per-user filtered chat history (used after `backfill:message-visibility`) |

`fieldOverrides` enable collection-group queries on:

- `comments.authorUid` — profile "Answers" tab.
- `followers.uid` — cross-collection follower lookups.
- `following.uid` — cross-collection following lookups.

## Realtime Database usage

[`database.rules.json`](../../database.rules.json) — RTDB is used **only** for ephemeral signals:

- `presence/{uid}` — `{ online: bool, lastSeen: serverTimestamp }`. Auth-only read; only the user themselves can write. `onDisconnect` flips to offline ([`lib/src/services/presence_service.dart:33-46`](../../lib/src/services/presence_service.dart)).
- `typing/{chatId}/{uid}` — `true` while typing. Auth-only read; only the user themselves can write. `onDisconnect().remove()` clears stale flags ([`lib/src/services/typing_service.dart:11-24`](../../lib/src/services/typing_service.dart)).

The default deny is implicit; no other paths are matched.

## Firebase Storage

[`storage.rules`](../../storage.rules) is intentionally minimal because new media goes to Supabase:

- `avatars/{uid}/{allPaths=**}` — public read, owner-only write.
- `posts/{uid}/{allPaths=**}` — auth-required read, owner-only write.

Everything else (including chat media, voice messages, story media, documents) is uploaded to Supabase Storage via the edge function below.

## Supabase setup

[`supabase/`](../../supabase) contains:

- [`DEPLOY.md`](../../supabase/DEPLOY.md) — deploy notes (not read here; check if needed).
- [`rls_policies.sql`](../../supabase/rls_policies.sql) — Supabase RLS policies for the storage buckets.
- [`functions/issue-upload-url/index.ts`](../../supabase/functions/issue-upload-url/index.ts) — the single deployed edge function.

### Edge function: `issue-upload-url`

Verifies a **Firebase ID token** (via `jose` + Firebase's JWKS at `https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com`) and returns a signed Supabase Storage upload URL scoped to that user's folder.

- **Request body:** `{ bucket, kind, ext, subPath? }`.
- **Allowed buckets:** `avatars`, `posts` (line 15).
- **Allowed extensions** (lines 16-28): images (`jpg jpeg png webp gif heic`), audio (`m4a aac mp3 wav ogg`), video (`mp4 mov webm m4v 3gp`), documents (`pdf doc docx xls xlsx ppt pptx txt rtf csv zip`).
- **Path templates** (lines 92-147) — all start with `{uid}/` so Supabase RLS can scope:

  | Kind | Path |
  |---|---|
  | `avatar` | `{uid}/avatar_{ts}.{ext}` |
  | `cover` | `{uid}/cover_{ts}.{ext}` |
  | `post` | `{uid}/posts/{ts}_{rand}.{ext}` |
  | `post-video` | `{uid}/posts/videos/{ts}_{rand}.{ext}` (video ext only) |
  | `story` | `{uid}/stories/{ts}_{rand}.{ext}` |
  | `story-video` | `{uid}/stories/videos/{ts}_{rand}.{ext}` (video ext only) |
  | `chat` | `{uid}/chats/{subPath}/{ts}_{rand}.{ext}` (subPath = chatId, alnum+`_` only) |
  | `chat-video` | `{uid}/chats/{subPath}/videos/{ts}_{rand}.{ext}` |
  | `chat-file` | `{uid}/chats/{subPath}/files/{ts}_{rand}.{ext}` (document ext only) |
  | `audio` | `{uid}/chats/{subPath}/voices/{ts}_{rand}.{ext}` (audio ext only) |

- **Response:** `{ uploadUrl, token, path, publicUrl }`. The Flutter [`storage_service.dart`](../../lib/src/services/storage_service.dart) then `PUT`s the file bytes to `uploadUrl` and stores `publicUrl` in Firestore (post media URL, chat message `imageUrl`, etc.).
- **Auth model** — `x-firebase-token` header carries the Firebase ID token (because the standard `Authorization` header must carry the Supabase anon key for Supabase's own gateway). Service-role key + `SUPABASE_URL` are env vars on the function side; client reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from `.env` ([`lib/src/services/storage_service.dart:20-21`](../../lib/src/services/storage_service.dart)).

The fallback handling in `StorageService.uploadStoryVideo` ([`lib/src/services/storage_service.dart:53-60`](../../lib/src/services/storage_service.dart)) notes that older deployments of the edge function don't whitelist `story-video` and it retries with `post-video`.

## Local env variables (`.env`)

Loaded by `flutter_dotenv` ([`lib/main.dart:60`](../../lib/main.dart)) and consumed by services:

| Key | Used by |
|---|---|
| `SUPABASE_URL` | [`storage_service.dart:20`](../../lib/src/services/storage_service.dart) |
| `SUPABASE_ANON_KEY` | [`storage_service.dart:21`](../../lib/src/services/storage_service.dart) |
| `USE_FIREBASE_EMULATOR` | [`main.dart:86-88`](../../lib/main.dart) — opt-in toggle, debug-mode only. |
| `FIREBASE_EMULATOR_HOST` | [`main.dart:90`](../../lib/main.dart) — defaults to `localhost`; set to LAN IP for physical device testing. Emulator ports: Auth 9099, Firestore 8080, Storage 9199, Functions 5001. |

Edge function side (Supabase secret vars, [`supabase/functions/issue-upload-url/index.ts:11-13`](../../supabase/functions/issue-upload-url/index.ts)):

- `FIREBASE_PROJECT_ID` (must equal `coil-50528`).
- `SUPABASE_URL`.
- `SUPABASE_SERVICE_ROLE_KEY`.

## Related files

- [`.firebaserc`](../../.firebaserc)
- [`firebase.json`](../../firebase.json)
- [`lib/firebase_options.dart`](../../lib/firebase_options.dart)
- [`firestore.rules`](../../firestore.rules)
- [`firestore.indexes.json`](../../firestore.indexes.json)
- [`database.rules.json`](../../database.rules.json)
- [`storage.rules`](../../storage.rules)
- [`functions/package.json`](../../functions/package.json)
- [`functions/src/index.ts`](../../functions/src/index.ts)
- [`supabase/functions/issue-upload-url/index.ts`](../../supabase/functions/issue-upload-url/index.ts)
- [`supabase/rls_policies.sql`](../../supabase/rls_policies.sql)
- [`lib/src/services/storage_service.dart`](../../lib/src/services/storage_service.dart)
- [`lib/src/services/presence_service.dart`](../../lib/src/services/presence_service.dart)
- [`lib/src/services/typing_service.dart`](../../lib/src/services/typing_service.dart)
- [`lib/src/services/fcm_service.dart`](../../lib/src/services/fcm_service.dart)
- [`lib/src/services/auth_service.dart`](../../lib/src/services/auth_service.dart)
- [`lib/main.dart`](../../lib/main.dart)
- [`ios/Runner/Info.plist`](../../ios/Runner/Info.plist)
