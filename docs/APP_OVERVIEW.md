# Iter / COIL — Application Overview & Technical Spec

> Living reference for the Iter (a.k.a. COIL) Flutter app. Every claim below was
> verified against the source on the date of writing. Where the code and a
> previously-assumed behavior diverge, the **code** is treated as truth.
>
> - **Frontend:** Flutter + Riverpod
> - **Auth & metadata:** Firebase Auth + Cloud Firestore
> - **Media storage:** Supabase Storage (via edge functions); Firebase Storage for custom stickers only
> - **Plan:** Firebase Spark (free) — no Cloud Functions in the live path

---

## 1. Authentication & Roles

| Aspect | Reality | Source |
| --- | --- | --- |
| Login methods | Email/Password, Google, Apple (Apple button iOS-only). **No phone/OTP login.** | `auth_service.dart`, `login_screen.dart:263-279` |
| "OTP" screen | Post-signup **email verification** only — not a login method | `otp_screen.dart:13-64` |
| Roles | `user` (default), `admin`, `org_admin` — stored as string field `role` | `admin_service.dart:714-746` |
| Event Manager storage | `role == 'org_admin'` (string value, **not** a boolean or permission list) | `admin_providers.dart:25-28` |
| Suspension | Firestore field `suspended: bool`, checked by app. **Not** Firebase Auth disable. No `isBanned`/`isActive`. | `admin_service.dart:711` |

There is **no User model class** — users are raw Firestore `Map<String,dynamic>` docs accessed via `currentUserDocProvider`.

---

## 2. Personalization & Recommendation

Only **events** are personalized. Posts are **not**.

**Profile fields used in scoring:** `field`, `goals[]`, `city`, `location {lat,lng}`.
(`profession` and `academicLevel` are collected but unused in the formula.)

**Event relevance score** (`event_screen.dart:63-97`, rule-based, no ML):

| Signal | Weight |
| --- | --- |
| `field` keyword appears in event title/subtitle/description/type | **+3** |
| Each `goal` keyword appears in event text | **+2** each |
| Goal ↔ event-type affinity (e.g. "Conferences" goal ↔ Conference type) | **+2** |
| User `city` == event city (exact, lowercased) | **+2** |
| User within 100 km of event (Haversine) | **+1** |

**Posts / Q&A / Travel feeds:** chronological (`createdAt desc`), filtered for blocked authors + privacy (private posts visible only to followers/self). Travel feed adds geo filtering. No scoring. (`post_providers.dart:45-104`, `post_service.dart`)

---

## 3. Events & Event Manager

- **Who can create:** `admin` and `org_admin` only. Enforced in UI **and** Firestore rules. (`firestore.rules:440-452`)
- **Becoming an event manager:** an `admin` manually sets `role: 'org_admin'` via `setRole()`, which notifies the user ("Event manager access granted"). (`admin_service.dart:714-746`)
- **Event approval after creation:** **None.** No status/approved/pending field on the event model — events go live immediately.
- **org_admin scope:** can create events, and edit/delete only the events they created (`createdByUid == request.auth.uid`).

**Required event fields** (`admin_events_screen.dart:782-814`): title, eventType, country, description, ≥1 image.
**Optional:** subtitle, city, funds, deadline, link, phone, email.

**Event registration / RSVP** (`event_registration_service.dart`):
- Collection `eventRegistrations`, deterministic ID `{eventId}_{uid}` (one per user per event).
- Status flow: **always starts `pending`** → admin `approve` / `reject`. There is **no** per-event auto-accept option. Status enum: `pending | approved | rejected`. Approve/reject notifies the user.
- Registration form requires: name, email, phone, countryCode.

---

## 4. Social Features

| Feature | State | Source |
| --- | --- | --- |
| Post types | Normal; Q&A/Discuss (`postType:'qa'` + `discussKind:'question'\|'discussion'`); Travel (geo posts). Field-driven, not a strict enum. | `post_model.dart:31`, `post_service.dart:260-261` |
| Stories | Fully implemented: image/video/text + overlays, viewer tracking, **24h expiry** | `story_service.dart:151-195` |
| Reposting | Implemented; **has admin toggle** `repostsEnabled` | `post_service.dart:747-793` |
| Comments | **Multi-level** (replies-to-replies via `parentCommentId`) | `comment_service.dart:50` |
| Save / bookmark | Yes — `users/{uid}/saved/{postId}` | `post_service.dart:828-851` |
| Reporting | Posts ✅, Discuss/Q&A ✅, User profiles ✅. **No** comment-level or per-discussion report. | `post_service.dart:133-207` |

---

## 5. Messaging

All message content types are supported (`chat_service.dart:13-93`):

text · images · videos · files (name/mime/size) · voice (+ on-device transcript) · location (lat/lng/label) · stickers (asset + custom) · polls · reactions (6 fixed emoji ❤️ 😂 😮 😢 🔥 👍) · reply/quote.

| Feature | State | Source |
| --- | --- | --- |
| Group chats | Full general groups (create/add/remove/rename) — not only event groups | `chat_service.dart:1040-1132` |
| Typing indicator | Yes — Firebase RTDB, auto-clears on disconnect | `typing_service.dart` |
| Online presence | Yes — `online` + `lastSeen`, 30s heartbeat, 90s stale-guard | `presence_service.dart` |
| Message requests | Yes — non-mutual-follow chats go to a requests inbox; auto-accepted on mutual follow | `chat_service.dart:986-1012` |

---

## 6. Translation

**Provider fallback order** (`translate_service.dart:387-417`):

- **Kurdish** (ckb / kmr / ku): Azure Primary → Azure Secondary → Gemini
- **Non-Kurdish:** Gemini → Azure Primary → Azure Secondary

| Aspect | Reality | Source |
| --- | --- | --- |
| Where it runs | **Client-side** direct HTTP. (`functions/src/translate.ts` exists but is **unused**.) | `translate_service.dart:305-628` |
| Local cache | SharedPreferences, key `src\|tgt\|sha1(text)`, 1000-entry cap, no TTL | `translate_service.dart:125-214` |
| Save translations | Yes — `users/{uid}/savedTranslations` | `saved_translations_screen.dart` |
| Per-chat auto-translate | Yes — per-chat toggle (`chat_autotranslate_{chatId}`) + global target language | `chat_screen.dart:149-160` |
| Speech-to-text | Yes — 40+ language locales (Kurdish → `ar_IQ`); some langs `stt:null` | `translate_service.dart:24-112` |
| Text-to-speech | Yes — `flutter_tts` | `translate_screen.dart` |

---

## 7. Censorship & Moderation

**Applied to:** Posts, Discuss/Q&A posts, Comments (+replies), Chat messages. **Not** events.
**Timing:** client-side pre-check before any Firestore write.

**Block vs mask — differs by content type:**

| Content | Behavior |
| --- | --- |
| Posts, Discuss posts | **Hard block** — throws, never saved |
| Comments, Chat messages | **Mask/hide** — real text kept sender-only, public copy emptied; author may clean & re-promote |

**Banned words:** Firestore `adminConfig/app.profanityWordsEn`, editable in admin settings, 10-min cache, hardcoded fallback list. (`admin_settings_screen.dart:200-221`, `profanity_filter_service.dart`)

**Report types (4):** post reports (`postReports`), discuss reports (`discussReports`), user-profile reports (`userReports`), error reports (`errorReports`). No comment-level reports.

---

## 8. Admin Configuration

**Feature toggles — exactly 3** (`admin_service.dart:77-79`): `storiesEnabled`, `repostsEnabled`, `translateEnabled`.
Comments, messaging, discuss, events, travel are **hardcoded on** (no toggle).

**Editable dynamic lists (6)** (`admin_settings_screen.dart:356-484`): event types, professions, fields, academic levels, goals, profanity words. (Countries are a static read-only list.)

**Banners (2):** `announcement` (free text) and `maintenanceMode` (boolean).
**Maintenance mode = banner only** — it does **not** block any feature. (`home_screen.dart:782-791`)

---

## 9. Error Reporting

**Saved fields** (`error_report_service.dart:143-155`): `message`, `stack`, `kind`, `screen`, `context`, `uid`, `platform`, `appVersion`, `resolved`, `createdAt`.
**Not captured:** device model, screen size.
Collection `errorReports`; rate-limited (25/session, 3s gap, 2-min dedup).

**User experience on error:** silent — logged to Firestore, app keeps running. **No** fallback screen, **no** alert dialog. (`error_report_service.dart:79-80`)

**Admin management** (`admin_error_reports_screen.dart`):
- Two tabs (Unsolved / Solved), search, rollup of most-frequent errors.
- Multi-select → bulk delete; top menu "Clear all solved".
- Per-report tile: **Copy** action only. (The redundant inline Mark-resolved/Delete buttons were removed — those actions are covered by multi-select delete + the resolved/solved tabs + "Clear all solved".)
- `setResolved` / `delete` still exist on the service (`errorReportAdminProvider`) and back the bulk/menu flows.

---

## 10. Database Structure

**Top-level Firestore collections:**
`adminConfig` · `users` · `posts` · `stories` · `chats` · `events` · `eventRegistrations` · `eventChats` · `notifications` · `postReports` · `discussReports` · `userReports` · `errorReports` · `blacklist` · `contactRequests` · `stickerPacks`

**Notable subcollections:** post `comments` / `likes` / `reposts` / `reactions`; user `saved` / `reposts` / `savedTranslations` / notification `items`; chat `messages`; eventChat `members`.

**Media storage split:**
- **Supabase Storage** — *all* user media (avatars, post images/videos, story media, chat media). Uploaded via edge functions that verify the Firebase ID token. Public read, service-role write.
- **Firebase Storage** — custom sticker `.webp` files only (`stickers/{uid}/{packId}/{index}.webp`).
- **Firestore** — all metadata.

---

## 11. Security Rules

Role helpers (`firestore.rules:4-33`): `signedIn()`, `isAdmin()`, `isOrgAdmin()`, `isSelf(uid)`.

- `admin` — full reach (users, config, reports, all events).
- `org_admin` — events only; create any, edit/delete only own (`createdByUid`); may clear `new_event` notifications for own events.
- `isSelf` — guards personal subcollections (followers, following, saved, visitor traces, etc.).
- Error reports: anyone may create; only admins read/update(`resolved`)/delete.
- Event registrations: user creates own as `pending`; only admin updates status.

**Admin surface:** **in-app only** — ~14 admin screens under `lib/src/features/screens/admin/`, gated by role. No separate web/admin app.

---

## Known gaps / things explicitly NOT present

- No phone/OTP **login**.
- No ML personalization; posts not personalized at all.
- No event approval workflow (events are live on create).
- No comment-level or per-discussion reporting.
- No device-model / screen-size capture in error reports.
- No error fallback screen (silent logging).
- Maintenance mode does not gate features.
- Firebase Cloud Functions are not in the live path (Spark plan); the `functions/` translate function is unused.
