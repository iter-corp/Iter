# Vision and Purpose

## What the app IS

The Flutter package name is `coil` ([`pubspec.yaml:1`](../../pubspec.yaml)) and the project root is named `COIL-project`, but the user-facing brand is **Iter**:

- iOS `CFBundleDisplayName` / `CFBundleName` = `Iter` ([`ios/Runner/Info.plist:10,18`](../../ios/Runner/Info.plist)).
- iOS bundle id = `com.iter.ai`; Android `applicationId` / `namespace` = `com.iter.ai` ([`android/app/build.gradle.kts:12,27`](../../android/app/build.gradle.kts)).
- Permission strings all begin with "Iter needs..." ([`ios/Runner/Info.plist:30,32,34,36`](../../ios/Runner/Info.plist)).
- `pubspec.yaml` description: "Coil — Social community app".

Treat `Coil` as the internal codename (Firebase project, package, repo) and `Iter` as the shipping product name. The Firebase project id is `coil-50528` ([`.firebaserc`](../../.firebaserc), [`lib/firebase_options.dart:53`](../../lib/firebase_options.dart)).

## Problem it solves / what it does

Iter is a **social community app** combining a feed, stories, group/private chat, organized events, and a built-in translator. From verified code:

- **Feed of posts** — text/image/video posts with likes, comments, reposts, saves, Q&A threads, and per-post Discuss topics ([`lib/src/providers/post_providers.dart`](../../lib/src/providers/post_providers.dart), [`firestore.rules:265-367`](../../firestore.rules)).
- **Stories** — 24h-style story items with viewers tracking, comments, and likes ([`lib/src/services/story_service.dart`](../../lib/src/services/story_service.dart), [`firestore.rules:369-413`](../../firestore.rules)).
- **Events** — admin / "org admin" managed events (`adminEvents`, registration requests, event group chats with polls) ([`firestore.rules:415-544`](../../firestore.rules), [`lib/src/services/event_registration_service.dart`](../../lib/src/services/event_registration_service.dart)).
- **Direct & group chat** — 1:1 and group threads with reactions, polls, voice messages, stickers, replies, "delete for everyone", typing indicators, presence ([`lib/src/services/chat_service.dart`](../../lib/src/services/chat_service.dart), [`lib/src/services/typing_service.dart`](../../lib/src/services/typing_service.dart), [`lib/src/services/presence_service.dart`](../../lib/src/services/presence_service.dart)).
- **Translate tab** — speech-to-text + on-device TTS + translate (uses `@google-cloud/translate` in [`functions/package.json`](../../functions/package.json) and `lib/src/services/translate_service.dart`).
- **Live broadcast** — Agora RTC engine integration ([`pubspec.yaml:46`](../../pubspec.yaml), `functions/src/live.ts` for token issuing).
- **Multi-language** — English, Arabic, Kurdish (Sorani / `ckb`) with full RTL ([`lib/src/providers/locale_provider.dart:14-17`](../../lib/src/providers/locale_provider.dart)).

## Target audience

Inferred from code, not marketing copy:

- Tri-lingual UI (`en` / `ar` / `ckb`) with Kurdish Sorani as a first-class option and a custom localizations delegate ([`lib/src/l10n/ckb_material_localizations.dart`](../../lib/src/l10n/ckb_material_localizations.dart)) → audience is Iraq / Kurdistan region / Arabic-speaking communities.
- The "Connect" tab uses geolocation to show "people near you" ([`ios/Runner/Info.plist:39`](../../ios/Runner/Info.plist) location-when-in-use description).
- "Org admin" role granted via a contact-us / organization-application flow ([`firestore.rules:29-33,663-686`](../../firestore.rules)) → suggests local organizations / NGOs / clubs publishing community events.

## Primary user flows

Derived from [`lib/src/router/app_router.dart`](../../lib/src/router/app_router.dart) redirects:

1. **First boot** — `/splash` → if unauth → `/login`.
2. **Signup** — `/signup` → `/otp` (email verification) → `/onboarding` (writes `username`, profile, location) → `/app-intro` → `/home`.
3. **Returning user** — `/splash` → `/home` once user doc loads.
4. **Force-update gate** — `_VersionGate` blocks the app if installed version < `adminConfig.minAppVersion` ([`lib/main.dart:355-413`](../../lib/main.dart)).
5. **Push-driven flow** — FCM "new_event" notification opens `EventDetailScreen` directly via `Navigator.push` from `_handleFcmEvent` ([`lib/main.dart:200-250`](../../lib/main.dart)).

### Five-tab home (bottom nav)

`MainScreen` is a `PageView` over five tabs ([`lib/src/features/model/main_screen.dart:29-46,112-119`](../../lib/src/features/model/main_screen.dart)):

| Index | Icon asset | Screen | Purpose |
|---|---|---|---|
| 0 | `Home.svg` | `HomeBody` | Feed + stories |
| 1 | `Event.svg` (rendered as `Icons.diversity_3_rounded`) | `EventBody` | Events / community |
| 2 | `Translate.svg` | `TranslateBody` | Translator |
| 3 | `Message.svg` | `MessageBody` | Inbox (with unread red-dot badge from `inboxProvider`) |
| 4 | `Profile.svg` | `ProfileScreen` | Self profile |

Note: there are two bottom-nav widgets — `BottomNav` in [`lib/src/features/widgets/botton_nav.dart`](../../lib/src/features/widgets/botton_nav.dart) (filename typo retained) appears to be the older standalone version; the active in-app bar is the inline blurred glass-pill nav built directly inside `MainScreen.build` with an `AnimatedPositionedDirectional` selector bubble.

## What makes it distinct

Concretely visible in the codebase:

- **First-class Kurdish (ckb) support** — custom Material/Cupertino/Widgets localization delegates that re-use Arabic delegate behavior for RTL, since Kurdish Sorani isn't bundled with Flutter ([`lib/main.dart:309-319`](../../lib/main.dart), [`lib/src/l10n/ckb_material_localizations.dart`](../../lib/src/l10n/ckb_material_localizations.dart)).
- **Two-tier admin model** — full `admin` and limited `org_admin` (event-create-only) roles, with rules enforcing each ([`firestore.rules:19-41`](../../firestore.rules)).
- **In-app error reporting** — uncaught errors flow into the `errorReports` Firestore collection with strict shape validation, rate-limited per session ([`lib/src/services/error_report_service.dart:17-30`](../../lib/src/services/error_report_service.dart), [`firestore.rules:60-84`](../../firestore.rules)).
- **Profanity filter** ([`lib/src/services/profanity_filter_service.dart`](../../lib/src/services/profanity_filter_service.dart)) checked before posting / commenting.
- **Live presence + typing via RTDB**, not Firestore ([`lib/src/services/presence_service.dart`](../../lib/src/services/presence_service.dart), [`lib/src/services/typing_service.dart`](../../lib/src/services/typing_service.dart), [`database.rules.json`](../../database.rules.json)).
- **Hybrid storage** — Supabase Storage (via signed-URL edge function) for user media; Firebase Storage only for `avatars/` and `posts/` legacy paths ([`lib/src/services/storage_service.dart`](../../lib/src/services/storage_service.dart), [`supabase/functions/issue-upload-url/index.ts`](../../supabase/functions/issue-upload-url/index.ts), [`storage.rules`](../../storage.rules)).
- **Live audio/video via Agora** for broadcasts ([`pubspec.yaml:46`](../../pubspec.yaml), [`functions/src/live.ts`](../../functions/src/live.ts)).

## Related files

- [`lib/main.dart`](../../lib/main.dart)
- [`lib/src/router/app_router.dart`](../../lib/src/router/app_router.dart)
- [`lib/src/features/model/main_screen.dart`](../../lib/src/features/model/main_screen.dart)
- [`lib/src/features/widgets/botton_nav.dart`](../../lib/src/features/widgets/botton_nav.dart)
- [`pubspec.yaml`](../../pubspec.yaml)
- [`ios/Runner/Info.plist`](../../ios/Runner/Info.plist)
- [`android/app/build.gradle.kts`](../../android/app/build.gradle.kts)
- [`.firebaserc`](../../.firebaserc)
- [`lib/firebase_options.dart`](../../lib/firebase_options.dart)
- [`firestore.rules`](../../firestore.rules)
