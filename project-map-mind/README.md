# Project Map-Mind

A complete handoff knowledge base for the **Iter** (codename `Coil`) Flutter + Firebase social-community app.

**Read this first** if you are an AI or new developer trying to understand the project — every file here is grounded in the actual source code with clickable links to specific files and line numbers. No marketing fluff, no invented details.

## How to use this folder

Each subfolder covers one slice of the project, ordered from highest-level to most specific:

1. **`overview/`** — what the app is, what tech it uses, how the layers fit together. Start here.
2. **`features/`** — one deep-dive per app feature (auth, home feed, posts, stories, chat, events, profile, admin, notifications, etc.).
3. **`backend/`** — Firestore schema, security rules, Cloud Functions, Realtime Database, Storage, FCM, Supabase edge functions.
4. **`frontend-layers/`** — cross-cutting Flutter infrastructure (router, providers, services, theme, l10n, error reporting, lifecycle).
5. **`flows/`** — end-to-end user journeys (signup, post creation, chat, event registration, follow, block/report, etc.).
6. **`glossary/`** — terms, naming conventions, code patterns, known gotchas.

Files are numbered (`01-`, `02-`, …) in suggested reading order within each folder.

## Map

### `overview/`

| File | What it covers |
|---|---|
| [01-vision-and-purpose.md](overview/01-vision-and-purpose.md) | Brand (`Coil` codename, `Iter` ship name), what the app does, target audience, primary flows |
| [02-tech-stack.md](overview/02-tech-stack.md) | Every dependency in `pubspec.yaml` + Android/iOS native config |
| [03-architecture.md](overview/03-architecture.md) | Layer diagram, `lib/src/` folder structure, example data flows, boot sequence |
| [04-firebase-and-supabase-setup.md](overview/04-firebase-and-supabase-setup.md) | Project IDs, enabled services, indexes, RTDB paths, Storage rules, Supabase edge function |

### `features/`

| File | Feature |
|---|---|
| [01-auth-and-onboarding.md](features/01-auth-and-onboarding.md) | Splash, intro, email/Google/Apple auth, email verification, onboarding form |
| [02-home-feed.md](features/02-home-feed.md) | Feed / Travel / Discuss modes, search, banners, stories strip |
| [03-posts.md](features/03-posts.md) | Composer, post card, like/comment/share/save/repost/report/Discuss-this-post |
| [04-comments-and-discuss.md](features/04-comments-and-discuss.md) | Regular comments vs QA threads, sender-only profanity, translation, deep-links |
| [05-stories.md](features/05-stories.md) | Image/video/text stories, overlays, viewer, 24h TTL, reply |
| [06-chat-and-messaging.md](features/06-chat-and-messaging.md) | 1:1, group, event chats; 10+ message types; cache; presence/typing |
| [07-events.md](features/07-events.md) | Event types, funding statuses, registration, event chats, per-user notif prefs |
| [08-profile-and-user.md](features/08-profile-and-user.md) | Owner vs other profiles, tabs, follow/block, settings, visitors |
| [09-admin.md](features/09-admin.md) | Admin dashboard, role gating, all sub-screens, `org_admin` |
| [10-notifications.md](features/10-notifications.md) | 3 categories, mark-as-read UX, deterministic dedupe, FCM, APNS race |
| [11-misc-features.md](features/11-misc-features.md) | Translate, saved translations, contact-us, chat requests, gallery, image viewer, language picker |

### `backend/`

| File | What it covers |
|---|---|
| [01-firestore-schema.md](backend/01-firestore-schema.md) | Every collection + sub-collection with field shapes |
| [02-cloud-functions.md](backend/02-cloud-functions.md) | All 16 exports across 8 source files, triggers, client wiring |
| [03-security-rules.md](backend/03-security-rules.md) | Section-by-section walkthrough of `firestore.rules` + RTDB + Storage rules |
| [04-realtime-database.md](backend/04-realtime-database.md) | `presence/{uid}` and `typing/{chatId}/{uid}` paths, `onDisconnect` pattern |
| [05-storage.md](backend/05-storage.md) | Supabase Storage path layout, allowed types, legacy Firebase Storage carve-out for stickers |
| [06-fcm-push.md](backend/06-fcm-push.md) | Token lifecycle, per-type title/body, deep-link routing, known gaps |
| [07-supabase.md](backend/07-supabase.md) | Edge function flow (JWT verify → signed upload URL), buckets, RLS, deploy |

### `frontend-layers/`

| File | What it covers |
|---|---|
| [01-router-and-navigation.md](frontend-layers/01-router-and-navigation.md) | GoRouter routes, auth gate, bottom-nav, FCM tap routing, `_VersionGate` |
| [02-state-providers.md](frontend-layers/02-state-providers.md) | Every provider across 18 files, grouped by domain |
| [03-services.md](frontend-layers/03-services.md) | All 26 service classes, public methods, Firestore touchpoints |
| [04-theme-and-design-system.md](frontend-layers/04-theme-and-design-system.md) | `AppColors`, theme tokens, `AppGlassCard`, `AppPageBackground`, system UI |
| [05-localization.md](frontend-layers/05-localization.md) | 3 languages, ~1253 keys, fallback, custom Kurdish delegate, RTL, add-key workflow |
| [06-utils-and-helpers.md](frontend-layers/06-utils-and-helpers.md) | Responsive, AppFeedback, maps_links, MediaCache, share_app |
| [07-error-reporting.md](frontend-layers/07-error-reporting.md) | 3 capture paths, screen tracking, rate limiting, `errorReports/` shape |
| [08-lifecycle-and-presence.md](frontend-layers/08-lifecycle-and-presence.md) | App-wide WidgetsBindingObserver, presence, sign-in/out side effects |

### `flows/`

| File | Flow |
|---|---|
| [01-signup-onboarding-flow.md](flows/01-signup-onboarding-flow.md) | Signup → email verify → onboarding → app intro → home |
| [02-login-flow.md](flows/02-login-flow.md) | Email, Google (with intent gate), Apple, forgot password |
| [03-create-post-flow.md](flows/03-create-post-flow.md) | Compose → upload → Firestore → feed fan-out |
| [04-like-comment-flow.md](flows/04-like-comment-flow.md) | Like and comment, notification fan-out (and the duplicate-notif bug) |
| [05-discuss-thread-flow.md](flows/05-discuss-thread-flow.md) | Discuss-this-post → QA topic creation → replies |
| [06-story-flow.md](flows/06-story-flow.md) | Create story (3 types) → publish → view → 24h client-side expiry |
| [07-chat-flow.md](flows/07-chat-flow.md) | Open chat → send message → cache → CF push (and the unread double-bump bug) |
| [08-event-flow.md](flows/08-event-flow.md) | Browse → register → admin approve → addMember separately → notify |
| [09-follow-flow.md](flows/09-follow-flow.md) | Public follow vs private follow request, accept/reject paths |
| [10-block-and-report-flow.md](flows/10-block-and-report-flow.md) | Block (no notif) and 3 report types |
| [11-admin-moderation-flow.md](flows/11-admin-moderation-flow.md) | Dashboard, take-downs, cascade delete user, Spark-plan auth-record limitation |
| [12-notification-flow.md](flows/12-notification-flow.md) | 20+ notification types, push pipeline, generic-body fallthroughs |
| [13-language-and-theme-toggle-flow.md](flows/13-language-and-theme-toggle-flow.md) | Locale + theme toggle, SharedPreferences, RTL rebuild |
| [14-app-resume-flow.md](flows/14-app-resume-flow.md) | Pause/resume, presence, video codec recreate, sign-in/out side path |

### `glossary/`

| File | What it covers |
|---|---|
| [01-glossary.md](glossary/01-glossary.md) | ~60 alphabetical entries: models, features, roles, enums, internal terms |
| [02-naming-conventions.md](glossary/02-naming-conventions.md) | File/class/provider/service/Firestore/l10n naming rules with tables |
| [03-conventions-and-patterns.md](glossary/03-conventions-and-patterns.md) | Riverpod patterns, `AsyncValue.when`, optimistic updates, glass-card pattern, `_VersionGate`, video lifecycle, `AppFeedback`, presence `onDisconnect` |
| [04-known-gotchas.md](glossary/04-known-gotchas.md) | Lifecycle traps, codec/surface gotcha, Kurdish delegate, Discuss-reuses-posts, project IDs, etc. |

## Known issues / open bugs (surfaced during research)

Things the research agents discovered that aren't bugs in the docs themselves but in the **app**, worth fixing eventually:

- **Duplicate notification docs on `like` and regular-post `comment`** — client writes a deterministic-id notif, Cloud Function (`onLikeCreate` / `onCommentCreate`) writes an auto-id notif. Recipient gets two docs and two pushes. See [flows/04-like-comment-flow.md](flows/04-like-comment-flow.md).
- **Chat `unread` counter double-bumps** — both the client batch and `onMessageCreate` increment the receiver's unread. Counter drifts +1 per message. See [flows/07-chat-flow.md](flows/07-chat-flow.md).
- **Event approval doesn't auto-join event chat** — admin must explicitly call `addMember`. Probably intentional but easy to miss. See [flows/08-event-flow.md](flows/08-event-flow.md).
- **Stories never cleaned up server-side** — `expiresAt` is a client-side filter only; expired docs accumulate forever and Supabase media leaks. See [flows/06-story-flow.md](flows/06-story-flow.md).
- **Admin `deleteUser` cannot delete the Firebase Auth record** on Spark plan (the `adminDeleteUser` callable function exists but isn't deployed). Email goes to blacklist but the auth account remains, blocking future re-signup. See [flows/11-admin-moderation-flow.md](flows/11-admin-moderation-flow.md).
- **Many FCM push types fall through to a generic body** — `comment_like`, `repost`, `story_*`, `follow_request`, `follow_accept`, `event_*`, `role_update` have no specific title/body. See [backend/06-fcm-push.md](backend/06-fcm-push.md).
- **`onEventCreate` reads the entire `users` collection** per event creation. Has a self-noted scaling TODO. See [backend/02-cloud-functions.md](backend/02-cloud-functions.md).
- **`mutedFor` on chats is checked nowhere on the server** — the FCM dispatcher does NOT skip muted recipients despite a comment claiming so. See [backend/02-cloud-functions.md](backend/02-cloud-functions.md).
- **Five `onCall` Cloud Functions exist but no client invokes them** (`translateText`, `adminSuspendUser`, `adminDeleteUser`, `selfDeleteAccount`, `issueLiveToken`). Spark-plan-friendly because the Dart layer does the equivalent work directly — ready to swap once on Blaze. See [backend/02-cloud-functions.md](backend/02-cloud-functions.md).
- **Custom stickers** are the only thing still hitting Firebase Storage (`users/{uid}/stickers/...`) — and that path isn't covered by `storage.rules`, relying on implicit `getDownloadURL` access. See [backend/05-storage.md](backend/05-storage.md).
- **E2EE was removed** — legacy `enc` envelopes in chat messages now render as "🔒 Couldn't decrypt" / "Message unavailable". New messages are plaintext. See [features/06-chat-and-messaging.md](features/06-chat-and-messaging.md).

## How this was generated

Six parallel research agents each took a category, read the relevant source files exhaustively, and wrote the docs grounded in code citations. Every file:line link in this knowledge base is verifiable. If anything seems wrong, trust the source code and update the doc — not the other way around.

If you're an AI reading this for the first time: spend ~10 minutes reading `overview/` and `glossary/01-glossary.md` first. Then jump to the specific `features/`, `backend/`, or `flows/` doc that matches your task.
