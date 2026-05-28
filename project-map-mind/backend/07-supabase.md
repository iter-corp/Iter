# Supabase

Supabase is used **only as a media-storage backend**. The app's identity, social graph, posts, chats, etc. live in Firebase. Supabase exists because Firebase Storage on the Spark plan does not allow generating signed upload URLs scoped per-user from the client safely, and the project wanted direct-to-bucket uploads without paying for the Firebase Blaze plan + Cloud Functions storage signing.

Project ref / URL hardcoded in the deploy notes: `htiwlasyspclmsyslaco.supabase.co` (project ID `coil-50528` is the Firebase side). The Flutter client reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from `.env` ([`storage_service.dart:20-21`](../../lib/src/services/storage_service.dart)).

## Architecture

```
                    [Flutter client]
                          │
                          │ 1. POST /functions/v1/issue-upload-url
                          │    headers: apikey=anon, X-Firebase-Token=<idToken>
                          ▼
                  ┌──────────────────────┐
                  │ Supabase Gateway     │
                  │ (validates anon key) │
                  └───────────┬──────────┘
                              ▼
                  ┌──────────────────────────┐
                  │ Edge Function:           │
                  │ issue-upload-url         │
                  │ (verifies Firebase JWT,  │
                  │ builds path, signs URL)  │
                  └───────────┬──────────────┘
                              │
                              │ 2. uses SERVICE_ROLE_KEY to call
                              │    storage.createSignedUploadUrl
                              ▼
                  ┌──────────────────────────┐
                  │ Supabase Storage         │
                  │ buckets: avatars, posts  │
                  └──────────────────────────┘
                              ▲
                              │ 3. client PUTs bytes with the signed URL
                              │    + token + Content-Type
                              │
                    [Flutter client]
```

Why service-role: storage RLS policies in [`rls_policies.sql`](../../supabase/rls_policies.sql) only allow `service_role` to write the two buckets. The client never has service-role access; only the edge function does. This means an attacker can't forge an upload to someone else's folder even if they bypass the client, because the edge function's path builder always uses the verified Firebase uid as the leading path segment.

## Edge function — [`supabase/functions/issue-upload-url/index.ts`](../../supabase/functions/issue-upload-url/index.ts)

Runtime: Deno. Single endpoint, POST-only.

### Request

```jsonc
{
  "bucket": "avatars" | "posts",
  "kind":   "avatar" | "cover" | "post" | "post-video" | "story" | "story-video"
          | "chat" | "chat-video" | "chat-file" | "audio",
  "ext":    "jpg" | "png" | ... ,
  "subPath": "<chatId>"     // only for chat / chat-video / chat-file / audio
}
```

Headers:

- `Authorization: Bearer {SUPABASE_ANON_KEY}` — Supabase gateway gate.
- `apikey: {SUPABASE_ANON_KEY}` — same.
- `X-Firebase-Token: {Firebase ID token}` — verified inside the function using `jose.jwtVerify` against the JWKS at `https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com`, validating `iss == https://securetoken.google.com/{FIREBASE_PROJECT_ID}` and `aud == FIREBASE_PROJECT_ID`. The `sub` claim becomes the uid used in the storage path.

### Response

```jsonc
{
  "uploadUrl": "https://...",   // signed PUT URL
  "token":     "...",           // optional bearer for the PUT
  "path":      "<uid>/...",     // bucket-relative path
  "publicUrl": "https://..."    // what the client stores in Firestore
}
```

On bad input it returns `400 {error: 'bad bucket'|'bad ext'|'bad kind'|'bad subPath'}`. On a missing/invalid Firebase token, `401`.

### Path builder

See lines 92-147 in the edge function. Every output path is prefixed with the verified uid; chat-flavored kinds require `subPath` to match `^[A-Za-z0-9_]+$`; video kinds reject non-video extensions; audio rejects non-audio extensions; chat-file rejects non-document extensions. The exact path layout is documented in [`05-storage.md`](05-storage.md).

### Secrets

The function needs three runtime values:

- `SUPABASE_URL` — auto-injected.
- `SUPABASE_SERVICE_ROLE_KEY` — auto-injected.
- `FIREBASE_PROJECT_ID` — manually set to `coil-50528` per [`DEPLOY.md`](../../supabase/DEPLOY.md).

## RLS policies — [`supabase/rls_policies.sql`](../../supabase/rls_policies.sql)

Two buckets, four policies:

```sql
-- avatars
allow SELECT  for ANYONE   when bucket_id = 'avatars';
allow ALL     for service_role when bucket_id = 'avatars';

-- posts
allow SELECT  for ANYONE   when bucket_id = 'posts';
allow ALL     for service_role when bucket_id = 'posts';
```

The buckets are publicly readable so that the `publicUrl` written into Firestore (avatars, post images, chat attachments) works for every viewer without authentication. Writes are gated to service_role, which only the edge function holds.

## Client wrapper — [`lib/src/services/storage_service.dart`](../../lib/src/services/storage_service.dart)

`StorageService._uploadViaEdge(bucket, file, kind, subPath?)` does two HTTP calls:

1. `POST /functions/v1/issue-upload-url` (20s timeout) — receives `{uploadUrl, token, publicUrl}`.
2. `PUT uploadUrl` with `Content-Type: <ext-derived>`, `Authorization: Bearer {token}`, `x-upsert: true`, body = file bytes (90s timeout).

Returns the `publicUrl` to the caller. All Firestore writes (avatars on `users/{uid}`, post image arrays, chat attachments, story media) store these public URLs as their reference.

Public helpers exposed by `StorageService`:

| Helper | Bucket / kind | Used for |
| --- | --- | --- |
| `uploadAvatar(file)` | avatars / avatar | profile photo |
| `uploadCover(file)` | avatars / cover | cover photo |
| `uploadPostImage(file)` | posts / post | feed/post image |
| `uploadPostVideo(file)` | posts / post-video | feed/post video |
| `uploadStoryImage(file)` | posts / story | image stories |
| `uploadStoryVideo(file)` | posts / story-video → falls back to post-video | video stories |
| `uploadChatImage(file, chatId)` | posts / chat | chat image |
| `uploadChatVideo(file, chatId)` | posts / chat-video | chat video |
| `uploadChatFile(file, chatId)` | posts / chat-file | chat document attachment |
| `uploadChatAudio(file, chatId)` | posts / audio | voice messages |

## Deployment — [`supabase/DEPLOY.md`](../../supabase/DEPLOY.md)

The full bring-up flow (no CLI required):

1. Paste `rls_policies.sql` into Dashboard → SQL Editor → Run. Verify the four policies exist under Storage → policies.
2. Dashboard → Edge Functions → Create new function named exactly `issue-upload-url` and paste `index.ts` content.
3. Add the `FIREBASE_PROJECT_ID = coil-50528` secret to Edge Functions → Secrets.
4. Smoke-test: curl with no token returns `401 {"error":"missing bearer token"}`.

CLI path (for future use): `npm install -g supabase`, `supabase login`, `supabase link --project-ref htiwlasyspclmsyslaco`, `supabase functions deploy issue-upload-url`.

## Related files

- [`supabase/functions/issue-upload-url/index.ts`](../../supabase/functions/issue-upload-url/index.ts)
- [`supabase/rls_policies.sql`](../../supabase/rls_policies.sql)
- [`supabase/DEPLOY.md`](../../supabase/DEPLOY.md)
- [`lib/src/services/storage_service.dart`](../../lib/src/services/storage_service.dart)
