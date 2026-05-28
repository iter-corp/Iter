# Cloud Storage

The app uses **two storage backends**:

1. **Supabase Storage** (primary) — every user-uploaded media file. See [`07-supabase.md`](07-supabase.md) for the full edge-function flow.
2. **Firebase Storage** (legacy / niche) — custom sticker uploads only.

The Firebase Storage rules ([`storage.rules`](../../storage.rules)) define `avatars/` and `posts/` paths but those buckets are no longer the upload target. They remain in place so any legacy bytes still hosted on Firebase Storage stay readable.

---

## Supabase Storage path layout

`StorageService._uploadViaEdge` ([`storage_service.dart:93-221`](../../lib/src/services/storage_service.dart)) POSTs to `${SUPABASE_URL}/functions/v1/issue-upload-url` with `{bucket, kind, ext, subPath?}`. The edge function builds the actual object path. Every path begins with `{uid}/` so a future RLS policy can scope rights to the owner.

| Bucket | Kind | Resulting path | Used for |
| --- | --- | --- | --- |
| `avatars` | `avatar` | `{uid}/avatar_{ts}.{ext}` | profile photo |
| `avatars` | `cover` | `{uid}/cover_{ts}.{ext}` | profile cover image |
| `posts` | `post` | `{uid}/posts/{ts}_{rand}.{ext}` | feed post image |
| `posts` | `post-video` | `{uid}/posts/videos/{ts}_{rand}.{ext}` | feed post video |
| `posts` | `story` | `{uid}/stories/{ts}_{rand}.{ext}` | image story |
| `posts` | `story-video` | `{uid}/stories/videos/{ts}_{rand}.{ext}` | video story (falls back to `post-video` for older edge deployments) |
| `posts` | `chat` (+ subPath = chatId) | `{uid}/chats/{chatId}/{ts}_{rand}.{ext}` | image attachment in chat |
| `posts` | `chat-video` (+ subPath) | `{uid}/chats/{chatId}/videos/{ts}_{rand}.{ext}` | chat video |
| `posts` | `chat-file` (+ subPath) | `{uid}/chats/{chatId}/files/{ts}_{rand}.{ext}` | chat document/file |
| `posts` | `audio` (+ subPath) | `{uid}/chats/{chatId}/voices/{ts}_{rand}.{ext}` | chat voice message |

## Allowed extensions (edge-function whitelist)

From [`supabase/functions/issue-upload-url/index.ts:16-28`](../../supabase/functions/issue-upload-url/index.ts):

- **Images:** `jpg`, `jpeg`, `png`, `webp`, `gif`, `heic`.
- **Audio:** `m4a`, `aac`, `mp3`, `wav`, `ogg`. (The Flutter client re-labels `m4a` to `aac` for the `audio` kind because older deployments rejected `m4a` — see [`storage_service.dart:131-136`](../../lib/src/services/storage_service.dart).)
- **Video:** `mp4`, `mov`, `webm`, `m4v`, `3gp`.
- **Docs:** `pdf`, `doc`, `docx`, `xls`, `xlsx`, `ppt`, `pptx`, `txt`, `rtf`, `csv`, `zip`.

The function additionally constrains `post-video` / `story-video` / `chat-video` to the video set, `chat-file` to the doc set, and `audio` to the audio set. Bad combos return `400 {error: 'bad kind'}` or `400 {error: 'bad ext'}`.

## File size limits

There are **no explicit size caps** in either the client `StorageService` or the edge function. The PUT to Supabase storage has a 90-second timeout client-side ([`storage_service.dart:202`](../../lib/src/services/storage_service.dart)) and a 20-second timeout for the upload-URL request. Supabase's own per-bucket size limit (configured in the dashboard) applies.

## Content-Type mapping

`StorageService._contentTypeOf` (lines 229-274) sets the `Content-Type` header on the PUT to Supabase based on the file extension — image/jpeg, image/png, image/webp, audio/m4a, audio/mpeg, video/mp4, application/pdf, application/zip, etc. Default for unknown extensions is `application/octet-stream`.

## Auth flow

1. Client gets `FirebaseAuth.instance.currentUser.getIdToken()`.
2. Client POSTs `{bucket, kind, ext, subPath?}` to `/functions/v1/issue-upload-url` with three headers: `Authorization: Bearer {SUPABASE_ANON_KEY}` (for the Supabase gateway), `apikey: {SUPABASE_ANON_KEY}` (same), and `X-Firebase-Token: {idToken}` (verified inside the function via Google's JWKS).
3. Edge function returns `{uploadUrl, token, path, publicUrl}` (lines 162-167).
4. Client PUTs the file bytes to `uploadUrl` with `Authorization: Bearer {token}` and `x-upsert: true`.
5. On success the client stores `publicUrl` in Firestore (post `imageUrls`, chat `imageUrl`, etc.).

## Who can upload / delete

- **Uploads:** anyone signed into Firebase. The edge function ensures the path always starts with the caller's Firebase uid; an attacker can't write to someone else's folder. The actual Supabase write is performed with the service-role key (`SUPABASE_SERVICE_ROLE_KEY`) — see [`rls_policies.sql`](../../supabase/rls_policies.sql).
- **Reads:** public for both `avatars` and `posts` buckets (so URLs embedded in Firestore docs work without auth) — see [`rls_policies.sql:13-23, 30-38`](../../supabase/rls_policies.sql).
- **Direct client deletes:** not supported. The note at [`chat_service.dart:1170-1175`](../../lib/src/services/chat_service.dart) acknowledges that when a chat is deleted, attached media remains orphaned in Supabase until a future cleanup job is built.

## Firebase Storage — what still uses it

[`StickerService.uploadCustomSticker`](../../lib/src/services/sticker_service.dart) (line 114) writes directly to Firebase Storage at `users/{uid}/stickers/{packId}/sticker_{ts}.webp` with `image/webp` content type. This path is **not** covered by the `storage.rules` (which only mention `avatars/` and `posts/`), so the implicit deny will block third-party reads — but this works in practice because the resulting download URL is the only access path and the client uses `getDownloadURL()` which always succeeds for the uploader. NOTE: this is a known gap; the rules should be widened or stickers should move to Supabase.

## Related files

- [`storage.rules`](../../storage.rules) — Firebase Storage rules (legacy)
- [`lib/src/services/storage_service.dart`](../../lib/src/services/storage_service.dart) — every Supabase upload helper
- [`lib/src/services/sticker_service.dart`](../../lib/src/services/sticker_service.dart) — the only direct Firebase Storage user
- [`supabase/functions/issue-upload-url/index.ts`](../../supabase/functions/issue-upload-url/index.ts) — edge function building paths
- [`supabase/rls_policies.sql`](../../supabase/rls_policies.sql) — bucket read/write policies
- [`supabase/DEPLOY.md`](../../supabase/DEPLOY.md) — deploy instructions
