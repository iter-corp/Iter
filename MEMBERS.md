# Iter — Graduation Presentation Plan

**Project:** **Iter — A Collaborative Opportunity Discovery and Student Engagement Platform**

**Total time:** 20 minutes, 5 presenters, ~4 minutes each.
**Format:** English slides, English speech, live demo at the end.
**Order on stage:** Honya → Naz → Zanyar → Mohammed → Kaziwa → Live Demo (driven by Honya or Naz).

This document tells each team member:
1. What slides they own.
2. What files to study in the codebase (full paths from the project root).
3. What to actually say (talking points).
4. What examiners will likely ask, and how to answer with confidence.

> The presentation deck has **17 slides** total. Slide numbers below reference the master deck (see the PowerPoint prompt in [PRESENTATION_PROMPT.md](PRESENTATION_PROMPT.md)).

---

## Slide-to-person map (at a glance)

| Slides | Person | Topic |
|--------|--------|-------|
| 1–2 | **Honya** | Title + Problem & Mission |
| 3–4 | **Naz** | User Journey + Frontend Architecture |
| 5–7 | **Zanyar** | Database schema + Security model (Firestore rules, RLS) |
| 8–11 | **Mohammed** | Personalization algorithm + Cloud Functions (the backend "brain") |
| 12–14 | **Kaziwa** | Verified-admin governance + Integrations (Agora, Supabase, Translate, FCM) |
| 15 | All 5 | Live demo |
| 16 | All 5 | Tech stack summary |
| 17 | All 5 | Q&A |

---

# Honya — Slides 1–2 (≈4 min)

## Role
Open the presentation. Frame **the problem Iter solves** and **the mission of the platform**.

## Slides she owns
- **Slide 1 — Title:** "Iter — A Collaborative Opportunity Discovery and Student Engagement Platform" + team names + date + university/department.
- **Slide 2 — Problem & Mission:** the fragmentation of opportunity, and how Iter addresses it.

## Files to study
- [README.md](README.md) and [FEATURES.md](FEATURES.md) — full feature catalogue, read end-to-end.
- [frontend/lib/main.dart](frontend/lib/main.dart) — app entry point: Firebase init, FCM listener, version gate, locale + theme wiring.
- [frontend/lib/src/features/screens/home_screen.dart](frontend/lib/src/features/screens/home_screen.dart) — the social feed users see first.
- [frontend/lib/src/features/model/main_screen.dart](frontend/lib/src/features/model/main_screen.dart) — the 5-tab bottom navigation (Home / Events / Translate / Messages / Profile).
- [frontend/lib/src/features/screens/auth/onboarding_screen.dart](frontend/lib/src/features/screens/auth/onboarding_screen.dart) — where a new user enters their academic profile.

## What to say

**Slide 1 — Title (30 sec):**
> "Good [morning/afternoon]. We're presenting **Iter** — a *Collaborative Opportunity Discovery and Student Engagement Platform*. I'm Honya, and with me are Naz, Zanyar, Mohammed, and Kaziwa. Iter is a full-stack mobile application built with Flutter, Firebase Cloud Functions, Cloud Firestore, Supabase storage, and Agora live audio/video. Over the next twenty minutes, we'll show you the problem we set out to solve, how the app is architected, and how every piece fits together to deliver opportunities to the right student at the right moment."

**Slide 2 — Problem & Mission (3 min 30 sec):**
> "In an increasingly interconnected academic landscape, students and researchers face one persistent and largely unaddressed challenge: **the fragmentation of opportunity**. Scholarships, internships, research programs, academic conferences, doctoral opportunities, hackathons, and community events are scattered across dozens of platforms, institutional portals, and informal networks. Discovery today depends on **proximity, privilege, or chance** — not on merit or fit.
>
> Iter was conceived as a direct response to that gap.
>
> Its mission is to be a **unified, student-native ecosystem** where opportunity discovery is not passive but **intelligent and tailored**. At the core of the platform lies a **profile-driven personalization engine** that filters and surfaces events based on the user's academic role, field of study, level of education, and stated goals. A computer-science undergraduate sees hackathons, technical internships, and coding programs. A doctoral researcher or faculty member sees grant calls, academic conferences, and research collaborations.
>
> Around that core, Iter is a full social platform — a feed for milestones, a discussion forum for academic dialogue, a connection system to discover peers worldwide, direct messaging for collaboration, and a built-in translation feature so language is never a barrier. Content credibility is maintained through a **verified-administrator governance model**: organizations, student unions, and academic institutions formally apply to become content partners. Iter is not an aggregator — it's a **trusted academic resource**.
>
> Finally, a **travel mode** extends the platform to international students and academic travelers by surfacing local opportunities nearby. Iter represents a holistic reimagining of how students engage with opportunity — not as something to stumble upon, but as something every student, regardless of background or geography, has an equal right to find."

## Likely examiner questions
- **"Who is the target user?"** → Students at every level (undergraduate, master's, PhD), researchers, faculty, and academic travelers. The personalization adapts content to each.
- **"How is this different from LinkedIn or Handshake?"** → LinkedIn is professional, not academic; Handshake is US-centric and one-employer-at-a-time. Iter is multilingual, region-aware, social-first, and operates an open verified-partner model rather than gating institutions behind paywalls.
- **"What platforms does it run on?"** → Flutter cross-platform: Android, iOS, and web from one codebase.
- **"How many screens does the app have?"** → 31 user-facing screens + 14 admin screens — `ls frontend/lib/src/features/screens` to count live.
- **"How do you ensure content is trustworthy?"** → Two layers: (1) verified-partner onboarding through the contact-us flow ([functions/src/adminUsers.ts](functions/src/adminUsers.ts)), and (2) Firestore Security Rules with role-based access (`isOrgAdmin`) that limit event creation to approved organizations.

---

# Naz — Slides 3–4 (≈4 min)

## Role
Walk the panel through **what the app feels like to use** and **how the frontend is built**.

## Slides she owns
- **Slide 3 — User Journey:** signup → onboarding profile → personalized feed/events → forum / chat / live → travel mode.
- **Slide 4 — Frontend Architecture:** Flutter + Riverpod + go_router + Material; folder structure; i18n with custom Kurdish delegate.

## Files to study
- [frontend/lib/src/router/app_router.dart](frontend/lib/src/router/app_router.dart) — every route and the auth-gating logic.
- [frontend/lib/src/features/screens/](frontend/lib/src/features/screens/) — list all 31 user-facing screens.
- [frontend/lib/src/features/widgets/personalization_fields.dart](frontend/lib/src/features/widgets/personalization_fields.dart) — the academic profile editor: profession (Student / Researcher / Professor / Traveler), field, academic level, goals.
- [frontend/lib/src/features/widgets/](frontend/lib/src/features/widgets/) — reusable widgets (`post_card`, `story_item`, `bottom_nav`, `event_detail`, `personalization_fields`).
- [frontend/lib/src/providers/](frontend/lib/src/providers/) — 18 Riverpod state providers.
- [frontend/lib/src/theme/app_theme.dart](frontend/lib/src/theme/app_theme.dart) — light/dark theme and brand colors.
- [frontend/lib/src/l10n/app_strings.dart](frontend/lib/src/l10n/app_strings.dart) + [strings_en.dart](frontend/lib/src/l10n/strings_en.dart) + [strings_ar.dart](frontend/lib/src/l10n/strings_ar.dart) + [strings_ckb.dart](frontend/lib/src/l10n/strings_ckb.dart) — translations.
- [frontend/lib/src/l10n/ckb_material_localizations.dart](frontend/lib/src/l10n/ckb_material_localizations.dart) — custom Kurdish Material localization (Flutter doesn't ship one).
- [frontend/pubspec.yaml](frontend/pubspec.yaml) — all Flutter dependencies.

## What to say

**Slide 3 — User Journey (2 min):**
> "A new user's path through Iter is intentionally short, then highly personalized:
> 1. **Splash** → Firebase initializes, FCM gets ready, the user's locale and theme load.
> 2. **Sign-up** → email/password, Google, or Apple. Apple uses a SHA-256-hashed nonce for security.
> 3. **Onboarding — the academic profile** → the user picks their **profession** (Student, Researcher, Professor, or Traveler), their **field of study** (Tech, Medicine, Law, Business, Arts, Engineering, Science, Education, Social sciences), their **academic level** (Undergraduate, Masters, PhD, Faculty), and their **goals** (Internships, Scholarships, Conferences, Research, Networking, Local events). The router blocks them from reaching the home feed until onboarding is complete — there is no anonymous browsing.
> 4. **Home feed** → social posts and milestones from peers they follow, plus a Stories row at the top.
> 5. **Events tab** → opportunities surfaced in **personalized order** by the relevance algorithm Mohammed will explain on slide 9. Travel mode toggles to local opportunities near the user's GPS location.
> 6. **Discussion forum** (the 'Discuss' tab inside posts) → Q&A threads for academic dialogue, with answer reactions and an Org-Admin moderation layer.
> 7. **Messages & live rooms** → 1-to-1 chats, group chats, voice messages, and Agora-powered live audio/video.
> 8. **Translate tab** → server-side Gemini translation with speech-to-text input and text-to-speech output, so language never blocks collaboration.
> 9. Admins and Org-Admins have a separate dashboard with 14 screens for verifying partners, publishing events, and moderating content."

**Slide 4 — Frontend Architecture (2 min):**
> "Under the hood:
> - **Flutter** with Dart — one codebase for Android, iOS, and web.
> - **Riverpod** for state management — 18 providers covering auth, posts, chats, follows, reactions, notifications, contact requests, polls, and so on. Compile-safe and async-first.
> - **go_router** for declarative navigation with auth-aware redirects: unauthenticated users can only reach `/login`, `/signup`, `/forgot-password`, or `/otp`; authenticated users who haven't completed onboarding are forced to `/onboarding` until they pick a username.
> - **flutter_localizations** with three languages: English, Arabic, and Kurdish Sorani. Flutter doesn't ship Kurdish localization, so we wrote a custom `CkbMaterialLocalizations` delegate that maps Kurdish onto the Arabic Material/Cupertino widgets — same RTL behavior, Arabic-script keyboards.
> - **Light and dark themes** with brand purple `#CE5DE5`.
> - **Image and video caching** via `cached_network_image` and `flutter_cache_manager` so a user scrolling the feed doesn't re-download media on every visit.
> - **Responsive layout** via a `ResponsiveBootstrap` widget that scales padding and font sizes across phones, tablets, and the web."

## Likely examiner questions
- **"Why Flutter and not React Native?"** → Single codebase for Android, iOS, and web. Flutter compiles to native ARM/x64 — better performance than React Native's JavaScript bridge. Material widgets give us a consistent design out of the box.
- **"Why Riverpod and not Provider or Bloc?"** → Compile-safe (no `Provider.of` runtime errors), supports async providers natively, and is easier to test.
- **"How do you handle right-to-left languages?"** → Flutter flips the entire widget tree automatically when the locale's language code is `ar` or `ckb`. The `Directionality` widget at the root flips every `Row`, `EdgeInsets`, and `Alignment`. Our custom `CkbMaterialLocalizations` delegate fills the gap Flutter leaves for Kurdish.
- **"How does navigation work?"** → `go_router` with declarative routes in [frontend/lib/src/router/app_router.dart](frontend/lib/src/router/app_router.dart). It watches the auth state via Riverpod's `refreshListenable` and redirects automatically when sign-in state or onboarding status changes.

---

# Zanyar — Slides 5–7 (≈4 min)

## Role
**Database schema** + **security model**. This is critical — examiners almost always probe security.

## Slides he owns
- **Slide 5 — Database overview:** Cloud Firestore + Realtime Database + Supabase Storage.
- **Slide 6 — Security Rules:** how `firestore.rules` blocks malicious clients.
- **Slide 7 — Supabase RLS + the verified-partner role model.**

## Files to study (read end-to-end at least twice)
- [firestore.rules](firestore.rules) — **646 lines**. The most important file Zanyar owns. Read every `match` block.
- [firestore.indexes.json](firestore.indexes.json) — composite indexes required by queries.
- [database.rules.json](database.rules.json) — Realtime Database rules for presence/typing.
- [supabase/rls_policies.sql](supabase/rls_policies.sql) — Row-Level-Security on Supabase storage.
- [supabase/DEPLOY.md](supabase/DEPLOY.md) — Supabase deployment notes.
- [supabase/functions/issue-upload-url/](supabase/functions/issue-upload-url/) — the edge function that signs upload URLs after verifying a Firebase ID token.
- [storage.rules](storage.rules) — Firebase Storage rules (used for some small assets).
- [firebase.json](firebase.json) — top-level Firebase project config.
- [functions/src/posts.ts](functions/src/posts.ts) — to understand the `feeds/{uid}/timeline/` collection that the timeline rule protects.
- [frontend/lib/src/services/auth_service.dart](frontend/lib/src/services/auth_service.dart) — to know what fields a new user document gets.

## What to say

**Slide 5 — Database (1 min 30 sec):**
> "Iter uses **two databases plus Supabase storage**:
>
> **Cloud Firestore** is our primary NoSQL document store. Top-level collections are:
> - `users/{uid}` — academic profile (profession, field, academicLevel, goals, city, location), plus sub-collections `followers`, `following`, `blockedUsers`, `saved`, `savedTranslations`, `visitors`, `reposts`.
> - `posts/{postId}` with sub-collections `likes`, `comments`, `reactions`, `privateComments`, `reposts`.
> - `stories/{storyId}` — 24-hour ephemeral milestones with `likes`, `comments`, `viewers`.
> - `chats/{chatId}` with `messages`, `reactions`, `polls`, `votes`.
> - `events/{eventId}` + `eventChats/{eventId}` with `members`, `messages`, `polls`.
> - `feeds/{uid}/timeline/{postId}` — pre-computed per-user social feed.
> - `notifications/{uid}/items/{itemId}` — per-user inbox.
> - `eventRegistrations/{eventId}_{uid}` — deterministic doc-id prevents duplicates.
> - `errorReports`, `postReports`, `userReports`, `discussReports` — moderation queues.
> - `blacklist/{email}` — banned-email tombstones.
> - `adminConfig` — feature flags, announcements, minimum-app-version gate.
> - `contactRequests/{requestId}` — the verified-partner application flow.
>
> **Firebase Realtime Database** is used for two things only: live presence (online/offline) and typing indicators. We picked RTDB for these because they need millisecond latency and don't need queries.
>
> **Supabase Storage** holds large media — post images, post videos, story media. The client uploads directly via signed URLs, bypassing Firebase's higher egress cost."

**Slide 6 — Firestore Security Rules (1 min 30 sec):**
> "The most important defensive code in the project is in [firestore.rules](firestore.rules) — 646 lines of declarative access policy that runs server-side on every read and write. Clients can never bypass it.
>
> Key patterns:
> - **Helper functions** — `signedIn()`, `isSelf(uid)`, `isAdmin()`, `isOrgAdmin()` for approved partner organizations, `isChatParticipant(chatId)`, and `canSeeContent(uid)` for private profiles.
> - **Role-based access** — full admins manage everything. Org-Admins can create and edit only **events they created**. Regular users can only modify their own data.
> - **Document-shape validation** — for example, the `errorReports` collection lets even unauthenticated users create a report so we capture boot crashes, but the rule validates field types, sizes, and forbids any extra keys. An attacker cannot dump arbitrary data through that opening.
> - **The `feeds/{uid}/timeline/` collection is read-only for the owner and write-blocked for everyone** — only the Cloud Function (admin SDK) can populate it. No one can inject fake posts into someone else's feed.
> - **Default deny** — the final block `match /{document=**} { allow read, write: if false; }` blocks anything we did not explicitly allow.
>
> We also have **server-authoritative counters**: clients cannot directly write `followersCount` or `likesCount`. Those fields are updated only by Cloud Functions via `FieldValue.increment`, so users cannot inflate their stats."

**Slide 7 — Supabase RLS & Verified-Partner Storage (1 min):**
> "Supabase Storage holds our large media. **Why two storage stacks?**
> - Firebase Storage egress gets expensive at scale.
> - Supabase lets the client upload directly via a signed URL — media bytes never pass through our Cloud Function.
>
> Security model:
> - **Public READ** on the bucket — anyone with the URL can fetch a post image, same as a CDN.
> - **WRITE is service-role only** — clients have only the `anon` key, which is RLS-restricted to public reads.
> - The flow: client calls our Supabase Edge Function `issue-upload-url`, the function verifies the Firebase ID token, checks the user is not blacklisted, then signs a short-lived upload URL with the `service_role` key. The client PUTs directly to Supabase Storage.
>
> An attacker who steals the Supabase anon key from a decompiled APK still cannot upload — they don't have a valid Firebase token."

## Likely examiner questions
- **"What stops a user from editing someone else's post?"** → The Firestore rule `allow update: if signedIn() && (resource.data.authorUid == request.auth.uid || isAdmin() || ...)` — only the author or an admin can edit. Non-authors can only bump `commentsCount` and `likesCount`. ([firestore.rules:264-269](firestore.rules#L264-L269))
- **"How do you stop spam likes?"** → The like document at `posts/{postId}/likes/{uid}` uses the user's UID as the doc ID, so each user can write at most one like per post. The counter is updated by the Cloud Function, not the client.
- **"Why NoSQL instead of SQL?"** → Three reasons: (1) Firestore scales horizontally with no DBA work; (2) sub-collection nesting fits social-graph data naturally — followers, comments, reactions sit under their parent; (3) real-time listeners are first-class — `snapshots()` streams update the UI live with no polling.
- **"How does an organization become a verified partner?"** → They open a `contactRequests` thread of type `organization`, an admin reviews their credentials, and on approval their user document's `role` is flipped to `org_admin`. The Firestore rules then let them create events, but only events where `createdByUid == request.auth.uid` — they cannot delete or edit other organizations' events.
- **"What's your backup strategy?"** → Firestore has automatic point-in-time recovery enabled in the Firebase Console. Restorable up to 7 days back.
- **"What about GDPR / data deletion?"** → A user can delete their account from profile settings. The `deleteUser` admin function in [functions/src/adminUsers.ts](functions/src/adminUsers.ts) cascades the delete across all sub-collections. A tombstone is written to `blacklist/{email}` so the same email cannot re-register without admin approval.

---

# Mohammed — Slides 8–11 (≈4 min)

## Role
**The personalization algorithm** + **Cloud Functions** (the backend brain).

This is where the *intelligent and tailored opportunity discovery* claim is defended. Examiners will probe the algorithm — Mohammed needs to know it by heart.

## Slides he owns
- **Slide 8 — Cloud Functions overview** (10 modules).
- **Slide 9 — The Personalization Algorithm** (event relevance scoring).
- **Slide 10 — Feed Architecture: fan-out-on-write**.
- **Slide 11 — Notification fan-out & Moderation.**

## Files to study (study slide 9's file first — it is the algorithm)
- **[frontend/lib/src/features/screens/event_screen.dart:62-97](frontend/lib/src/features/screens/event_screen.dart#L62-L97)** — `_eventRelevanceScore` function. The actual personalization algorithm. **Mohammed must memorize this scoring formula.**
- [frontend/lib/src/features/widgets/personalization_fields.dart](frontend/lib/src/features/widgets/personalization_fields.dart) — the profile fields the algorithm reads.
- [functions/src/index.ts](functions/src/index.ts) — module exports.
- [functions/src/posts.ts](functions/src/posts.ts) — fan-out-on-write social timeline (the "feed" code).
- [functions/src/likes.ts](functions/src/likes.ts) — like → notification.
- [functions/src/follows.ts](functions/src/follows.ts) — follower count + notifications.
- [functions/src/comments.ts](functions/src/comments.ts) — comment notifications + counter bumps.
- [functions/src/messages.ts](functions/src/messages.ts) — chat last-message preview + unread counts.
- [functions/src/notifications.ts](functions/src/notifications.ts) — FCM push fan-out.
- [functions/src/events.ts](functions/src/events.ts) — event creation → notify users who opted into that country/type.
- [functions/src/adminUsers.ts](functions/src/adminUsers.ts) — admin user-management endpoints.
- [functions/package.json](functions/package.json) — Node 20, firebase-admin, firebase-functions v2.
- [frontend/lib/src/services/profanity_filter_service.dart](frontend/lib/src/services/profanity_filter_service.dart) — client-side filter for messages and posts.

## What to say

**Slide 8 — Cloud Functions Overview (1 min):**
> "Our backend is **10 Cloud Functions modules**, all in TypeScript on Node 20. They split into two categories: **Firestore triggers** that fire automatically when documents change, and **callable functions** invoked directly from the client.
>
> | Module | Responsibility |
> |---|---|
> | `posts.ts` | Fan-out social timeline on post creation |
> | `likes.ts` | Notify post author on new like |
> | `follows.ts` | Update follower / following counters + notifications |
> | `comments.ts` | Comment notifications + counter bumps |
> | `messages.ts` | Chat last-message preview + unread increment |
> | `notifications.ts` | FCM push fan-out |
> | `events.ts` | New-event fan-out by country / type preference |
> | `live.ts` | Issues Agora RTC tokens (callable) |
> | `translate.ts` | Google Gemini translation proxy (callable) |
> | `adminUsers.ts` | Admin user-management endpoints (callable) |
>
> Everything runs server-side with the admin SDK, so security rules don't apply to functions — but they DO apply to clients. This is the core of our security model: **counters and side-effects only happen via Cloud Functions, never via direct client writes**."

**Slide 9 — The Personalization Algorithm (1 min 30 sec):**
> "Iter's central claim is that opportunity discovery should be **intelligent and tailored**, not chronological. Here is the algorithm that delivers on that.
>
> When the user opens the Events tab, every event is scored against the user's academic profile by the function `_eventRelevanceScore` in [event_screen.dart:62-97](frontend/lib/src/features/screens/event_screen.dart#L62-L97). The scoring formula is:
>
> | Signal | Weight |
> |---|---|
> | Event title / subtitle / description / type contains the user's **field of study** | **+3** |
> | Each of the user's **goals** matches anywhere in the event text | **+2 per goal** |
> | The event type matches a goal (e.g. goal = *Conferences* and `eventType` = *Conference*) | **+2** |
> | The user's **city** equals the event's city | **+2** |
> | The event is within **100 km** of the user's GPS coordinates | **+1** |
>
> Events are then sorted by score descending. So a Computer Science undergraduate with goals *Internships* and *Hackathons* sees tech internships and hackathons surfaced to the top — exactly the personalization promise.
>
> The algorithm runs client-side against the events stream, which means: (a) it is instant, (b) it respects privacy because the user's profile never leaves the device for scoring, and (c) it's deterministic so we can explain *why* each event was surfaced. There is **no machine-learning model**, **no opaque ranker** — this is by design. Students should understand why they see what they see."

**Slide 10 — Social Feed Architecture (45 sec):**
> "Separate from the Events surface, the social feed uses a classic **fan-out-on-write** design.
>
> When a user posts, the `onPostCreate` Cloud Function ([functions/src/posts.ts](functions/src/posts.ts)) writes a pointer to that post into every follower's personal `feeds/{followerUid}/timeline/` collection. The home screen then runs a single indexed query against the user's own timeline, so the feed loads in O(1) cost no matter how many people they follow.
>
> Writes batch in chunks of 450 (Firestore's batch limit is 500). Private accounts only fan out to accepted followers."

**Slide 11 — Notifications & Moderation (45 sec):**
> "Notifications work in two stages: a trigger writes a Firestore document to `notifications/{userUid}/items/{itemId}` (the in-app inbox), and a second `onCreate` trigger on that document fans out to FCM. So the inbox is always consistent even when push delivery fails.
>
> Moderation has three layers:
> 1. **Client-side profanity filter** ([profanity_filter_service.dart](frontend/lib/src/services/profanity_filter_service.dart)) — flagged content is marked `profanityFiltered: true`.
> 2. **Server-side message hook** — flagged messages skip the receiver's unread bump and push, so the sender sees their own message but no one else does.
> 3. **User reports** — four typed report collections, shape-validated, admin-only resolution."

## Likely examiner questions
- **"Is this machine learning?"** → No, and deliberately. It's a transparent rule-based scoring function so we can explain to any student *why* a specific event was surfaced. ML would be a black box and would also need a training dataset we don't have.
- **"Why are the weights what they are?"** → The hierarchy reflects our problem statement: field of study is the strongest signal because it filters out wrong-domain content entirely. Goals are next because they're explicit user intent. Geography is last because for academic opportunities, relevance > proximity — a great scholarship 500 km away beats a mediocre meetup next door.
- **"What if fan-out fails halfway through, e.g. 5000 followers?"** → We batch in groups of 450 (Firestore's max is 500). For very large follower counts, a Pub/Sub continuation would be the next step; our test accounts top out around 200 followers and complete in under 2 seconds.
- **"What if a user blocks me — do they still receive my posts?"** → Block enforcement is on the **read path**: the home screen filters out posts from blocked authors using `block_service.dart`. Fan-out still happens (simpler), but the post card never renders on the reader's side.
- **"Why TypeScript and not JavaScript?"** → Type safety. Firebase Functions v2 SDK is fully typed; we catch missing fields and wrong types at build time. Compiled output is plain Node.js — zero runtime cost.
- **"How do you test functions locally?"** → Firebase Emulator Suite. The Flutter app can connect with `USE_FIREBASE_EMULATOR=true` in `.env` — see [main.dart:85-99](frontend/lib/main.dart#L85-L99).

---

# Kaziwa — Slides 12–14 (≈4 min)

## Role
**Verified-partner governance** + **external integrations**. Show that Iter is a trusted academic resource, not a free-for-all aggregator, and that its integrations are wired securely.

## Slides he owns
- **Slide 12 — Verified-Partner Governance** (the contact-us → Org-Admin flow).
- **Slide 13 — Agora live audio/video + Supabase signed uploads.**
- **Slide 14 — Translation (Gemini), FCM push, travel mode.**

## Files to study
- [frontend/lib/src/features/screens/contact_us_screen.dart](frontend/lib/src/features/screens/contact_us_screen.dart) — the partner application UI.
- [frontend/lib/src/services/contact_request_service.dart](frontend/lib/src/services/contact_request_service.dart) — `promoteToOrgAdmin` and `revokeOrgAdmin`.
- [functions/src/adminUsers.ts](functions/src/adminUsers.ts) — admin user-role management.
- [firestore.rules](firestore.rules) — search for `isOrgAdmin` to see the role boundary.
- [functions/src/live.ts](functions/src/live.ts) — Agora token issuance.
- [supabase/functions/issue-upload-url/](supabase/functions/issue-upload-url/) — the upload-URL signer.
- [frontend/lib/src/services/storage_service.dart](frontend/lib/src/services/storage_service.dart) — Supabase client wrapper.
- [functions/src/translate.ts](functions/src/translate.ts) — Gemini translation Cloud Function.
- [frontend/lib/src/services/translate_service.dart](frontend/lib/src/services/translate_service.dart) — client side.
- [frontend/lib/src/features/screens/translate_screen.dart](frontend/lib/src/features/screens/translate_screen.dart) — UI with speech-to-text + TTS.
- [frontend/lib/src/services/fcm_service.dart](frontend/lib/src/services/fcm_service.dart) — FCM token registration.
- [frontend/lib/src/features/screens/event_screen.dart](frontend/lib/src/features/screens/event_screen.dart) — search for `_nearbyMode` to see travel mode.

## What to say

**Slide 12 — Verified-Partner Governance (1 min 15 sec):**
> "Iter's promise of trustworthy content rests on a **structured content-governance model**. Opportunities aren't user-submitted — they come from **verified partners**: organizations, student unions, and academic institutions.
>
> The flow:
> 1. An organization opens an `organization`-type contact request through the Contact Us screen.
> 2. An admin reviews their credentials in the admin dashboard.
> 3. On approval, the function `promoteToOrgAdmin` flips that user's `role` field from `user` to `org_admin`.
> 4. Firestore Security Rules then permit them to create events — but **only events where `createdByUid == request.auth.uid`**. They cannot edit or delete events owned by other partners.
> 5. If a partner misbehaves, `revokeOrgAdmin` instantly reverts their role to `user`. Their existing events remain (admins can purge them separately).
>
> This is enforced **in the rules engine, server-side** — not just in the UI. So a malicious Org-Admin who decompiled the app and tried to write directly to Firestore would still be blocked by the rule `request.resource.data.createdByUid == request.auth.uid`."

**Slide 13 — Agora Live + Supabase Uploads (1 min 30 sec):**
> "Two integrations, one shared security pattern: **never put a secret in the client**.
>
> **Agora live rooms.** When a user taps Go Live, the client calls [`live.issueLiveToken`](functions/src/live.ts) with the channel name and role (host or audience). The Cloud Function reads our Agora app secret from the server environment — never exposed to the client — and uses `agora-access-token` to mint a JWT signed with that secret, valid for one hour. The client uses the token to join the channel. Audio and video then stream **peer-to-peer through Agora's network**, never through our backend.
>
> **Supabase signed uploads.** When a user posts a photo, the client calls our Supabase Edge Function `issue-upload-url` with the Firebase ID token. The function verifies the token, checks the user is not blacklisted, generates a unique object key, signs a one-time upload URL using the Supabase `service_role` key, and returns it. The client PUTs the bytes directly to Supabase. Two wins: bytes never pass through our Cloud Function (no 10 MB function-payload limit, no egress cost), and the URL is one-time so it can't be replayed.
>
> Same pattern, different services: the secret stays server-side, and short-lived tokens authorize the client just-in-time."

**Slide 14 — Translation, Push, Travel Mode (1 min 15 sec):**
> "Three more integrations round out the platform:
>
> **Translation.** A built-in translate tab powered by Google Gemini ([translate.ts](functions/src/translate.ts)). The user types or speaks (`speech_to_text` Flutter plugin), the client sends to our Cloud Function, the function authenticates the user, validates source and target language, calls Gemini with a translation prompt, and returns the result. The translation is read back aloud via `flutter_tts`. Saved translations live under `users/{uid}/savedTranslations` for a personal academic phrasebook. Mission relevance: language never blocks cross-border collaboration on Iter.
>
> **Push notifications.** Firebase Cloud Messaging. The client registers tokens in `users/{uid}.fcmTokens` ([fcm_service.dart](frontend/lib/src/services/fcm_service.dart)); the `notifications.ts` Cloud Function fans out pushes whenever a notification document is created.
>
> **Travel mode.** Activated by toggling `_nearbyMode` on the Events tab. The app reads the user's GPS via the `geolocator` plugin, then surfaces events within ~100 km — the same distance threshold the personalization algorithm uses. This extends Iter to international students and academic travelers, exactly as the project brief promises."

## Likely examiner questions
- **"What stops a partner from impersonating another organization?"** → The Org-Admin role is granted only after an admin reviews their formal request in the contactRequests thread. Org-Admin events are also marked with `createdByUid`, which the rules engine ties to `request.auth.uid` — so even with credentials, they cannot author content as anyone but themselves.
- **"What happens if Agora is down?"** → The live room fails to connect with an error toast. The rest of the app keeps working — we don't store any data in Agora, just stream audio and video through it.
- **"Is the Supabase anon key safe to ship in the client?"** → Yes. That's what `anon` keys are designed for, paired with RLS policies that allow public read but block write. Writes require the `service_role` key, which lives only on the Edge Function server.
- **"Why Gemini for translation and not Google Cloud Translate?"** → Gemini handles mixed-language input better — academic content frequently mixes English with Arabic or Kurdish in one sentence, and Gemini produces more natural translations.
- **"What's travel mode's privacy posture?"** → GPS is only read when the user explicitly toggles `_nearbyMode`. The coordinates are sent to the relevance scorer running on-device — never to a server.

---

# Live Demo — Slide 15 (run on a phone, ≈2 min)

Driven by Honya or Naz from one device, mirrored to the projector via **Scrcpy** (Android) or **QuickTime** (iOS).

## Demo script — rehearse 5+ times

1. **Open the app** — already signed in as a seeded "Demo Student" account whose profile has `profession: Student`, `field: Tech`, `academicLevel: Undergraduate`, `goals: [Internships, Conferences, Hackathons]`. **Do NOT sign up live — it's slow.**
2. **Events tab** → point at the top event: "Notice the first event is a tech hackathon — that's the personalization algorithm in action. It scored highest because Tech is in the title and Hackathons matches my goal." Scroll once.
3. **Toggle Travel mode (Nearby)** → "Now I'm asking the app to prioritize events near my current GPS location."
4. **Home feed** → tap a post → like it → comment "Great milestone!" → close.
5. **Create a post** → photo + caption "Defense day 🎉" → publish. The post appears in the feed in ~2 seconds.
6. **Stories row** → tap a peer's story → swipe through.
7. **Discuss tab** (inside a post) → open a Q&A thread, react to an answer.
8. **Messages** → 1-to-1 chat → send a voice message (hold mic, "Hello panel!", release) → react with 👍.
9. **Translate tab** → type "Welcome to our defense" → translate to Kurdish → play TTS.
10. **Profile** → show profile-visitors list → toggle language to Arabic — the entire UI flips RTL. Toggle back.

## Backup plan
A pre-recorded 90-second screen capture (`assets/demo.mp4`) plays from the laptop if the live demo fails. Always have it loaded.

---

# Slide 16 — Tech Stack Summary (≈30 sec, any presenter)

| Layer | Tech |
|---|---|
| Frontend | Flutter, Dart, Riverpod, go_router, Material Design |
| Backend | Firebase Cloud Functions (Node 20 + TypeScript) |
| Database | Cloud Firestore (NoSQL) + Realtime Database (presence/typing) |
| Auth | Firebase Auth (Email + verification link, Google, Apple) |
| Storage | Supabase Storage (signed-URL uploads) + Firebase Storage |
| Live | Agora RTC |
| Translation | Google Gemini (via Cloud Function) |
| Notifications | Firebase Cloud Messaging |
| i18n | English · Arabic · Kurdish Sorani (custom delegate) |
| Platforms | Android, iOS, Web |

---

# Slide 17 — Q&A (final 1 min)

Open the floor. Whoever owns the most relevant slide answers first. If a question is unfamiliar, the default move is:

> "Great question — let me show you in the code."

Then `ctrl+click` the file path in your IDE — every file path in this document is correct and clickable.

---

# Prep checklist (do 48 hours before)

- [ ] Each person reads their assigned files at least twice.
- [ ] Each person can answer every "Likely examiner question" without notes.
- [ ] Mohammed has memorized the scoring formula on slide 9 verbatim.
- [ ] Demo rehearsed 5+ times end-to-end on the actual phone you'll use.
- [ ] Backup demo video recorded and loaded on the laptop.
- [ ] Seeded "Demo Student" account exists with: complete academic profile, 3+ posts, 2+ stories, 1+ event registration, an active chat with a received voice message, a saved translation.
- [ ] Phone fully charged, airplane-mode-off, USB cable + Scrcpy ready.
- [ ] Laptop has the slides + a copy of the repo open in VS Code.
- [ ] `flutter analyze` runs clean (info-level only — no warnings, no errors).
- [ ] Each person practices their ~4-minute slot with a timer. If you go over, cut a sub-bullet.

# Day-of checklist

- [ ] Test projector with your laptop **before** the room fills up.
- [ ] Open slides in **Presenter View** so you see your speaker notes.
- [ ] Open FEATURES.md and MEMBERS.md in a second window for grep-on-the-fly.
- [ ] Water on the podium.
- [ ] Smile. You built a real, working, multi-platform academic-opportunity platform with personalized discovery, verified-partner governance, real-time messaging, live video, and translation. Own it.
