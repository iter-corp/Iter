# Architecture

## High-level layers

```
┌──────────────────────────────────────────────────────────────────────┐
│ PRESENTATION                                                         │
│   lib/src/features/screens/*  ─ ConsumerWidget / ConsumerStatefulW   │
│   lib/src/features/widgets/*  ─ shared composables                   │
│   lib/src/features/model/*    ─ data models + MainScreen shell       │
│   lib/src/theme/app_theme.dart, lib/src/utils/responsive.dart        │
└──────────────────────────────▲───────────────────────────────────────┘
                               │  ref.watch / ref.read
                               │
┌──────────────────────────────┴───────────────────────────────────────┐
│ STATE (Riverpod)                                                     │
│   lib/src/providers/*  ─ StreamProvider / FutureProvider /           │
│                          StateNotifierProvider / Provider            │
│   lib/src/router/app_router.dart  ─ GoRouter + auth redirects        │
└──────────────────────────────▲───────────────────────────────────────┘
                               │  service.method(...) / streamX()
                               │
┌──────────────────────────────┴───────────────────────────────────────┐
│ SERVICE                                                              │
│   lib/src/services/*  ─ plain Dart classes wrapping Firebase /       │
│                         Supabase / HTTP. Stateless apart from a few  │
│                         caches (FcmService, MessageCache).           │
└──────────────────────────────▲───────────────────────────────────────┘
                               │  FirebaseFirestore / FirebaseDatabase
                               │  FirebaseStorage / FirebaseAuth / http
                               │
┌──────────────────────────────┴───────────────────────────────────────┐
│ DATA                                                                 │
│   Firestore   (posts, users, chats, events, notifications, reports)  │
│   RTDB        (presence/{uid}, typing/{chatId}/{uid})                │
│   Firebase    (FCM push, Auth)                                       │
│   Cloud Fns   (translate, agora token, fan-out, admin ops)           │
│   Supabase    (Storage via signed-URL edge function)                 │
└──────────────────────────────────────────────────────────────────────┘
```

## Directory map (`lib/src/`)

### `features/`

The UI layer. Three subfolders ([`lib/src/features/`](../../lib/src/features)):

- `screens/` — full-page screens. Each is typically a `ConsumerStatefulWidget` named `XxxScreen` (e.g. [`home_screen.dart`](../../lib/src/features/screens/home_screen.dart), [`event_screen.dart`](../../lib/src/features/screens/event_screen.dart), [`chat_screen.dart`](../../lib/src/features/screens/chat_screen.dart)). Sub-folders `auth/` and `admin/` group sign-in/onboarding screens and the admin dashboard.
- `widgets/` — re-used composable widgets (post cards, message bubbles, polls, stickers, profile widgets, bottom-nav, app-page background, location map, notification tile, etc.).
- `model/` — domain data classes: [`post_model.dart`](../../lib/src/features/model/post_model.dart), [`message_model.dart`](../../lib/src/features/model/message_model.dart), [`story_comment_model.dart`](../../lib/src/features/model/story_comment_model.dart), and `MainScreen` itself (the bottom-tab shell — [`main_screen.dart`](../../lib/src/features/model/main_screen.dart)).

Convention: screens read state via `ref.watch(xxxProvider)` and call mutations via `ref.read(xxxServiceProvider).method(...)`. Screens never talk to Firebase directly.

### `providers/`

Riverpod providers, one file per domain ([`lib/src/providers/`](../../lib/src/providers)). 19 files: `auth`, `admin`, `admin_report_notifications`, `block`, `chat`, `comment`, `contact_request`, `event_chat`, `event_registration`, `follow`, `locale`, `notification`, `poll`, `post`, `preferred_language`, `profile_visitor`, `reaction`, `story`, `theme`. Each typically exposes:

- A `*ServiceProvider` (`Provider<XxxService>`).
- Stream / future providers that subscribe to that service and shape results for the UI.

Example: `feedProvider` ([`lib/src/providers/post_providers.dart:45-70`](../../lib/src/providers/post_providers.dart)) combines three streams — posts, following list, blocked list — with `Rx.combineLatest3`, filtering blocked authors and private posts from non-followed users client-side.

### `services/`

Plain Dart classes that wrap external APIs ([`lib/src/services/`](../../lib/src/services)). 27 files. Pattern:

```dart
class XxxService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // … methods returning Future<T> or Stream<T> …
}
```

Notable services:

- [`auth_service.dart`](../../lib/src/services/auth_service.dart) — wraps `FirebaseAuth`, Google, Apple; carries `justSignedUp` flag for router.
- [`post_service.dart`](../../lib/src/services/post_service.dart) — feed, create-post (with profanity check), like, comment counters.
- [`chat_service.dart`](../../lib/src/services/chat_service.dart) — inbox, send/edit/delete messages, reactions, polls.
- [`storage_service.dart`](../../lib/src/services/storage_service.dart) — talks to the Supabase `issue-upload-url` edge function over HTTP and uploads to the returned signed URL.
- [`presence_service.dart`](../../lib/src/services/presence_service.dart) + [`typing_service.dart`](../../lib/src/services/typing_service.dart) — Realtime Database only (`presence/{uid}`, `typing/{chatId}/{uid}`).
- [`fcm_service.dart`](../../lib/src/services/fcm_service.dart) — singleton with a broadcast `Stream<FcmMessageEvent>` consumed by `_MyAppState` in `main.dart` to handle push taps.
- [`error_report_service.dart`](../../lib/src/services/error_report_service.dart) — wraps `runZonedGuarded`; writes to `errorReports` with rate limiting.
- [`message_cache.dart`](../../lib/src/services/message_cache.dart) — disk cache cleared on sign-out to prevent leaking previews to the next user on a shared device.
- [`profanity_filter_service.dart`](../../lib/src/services/profanity_filter_service.dart) — checks text against an admin-curated word list.

### `router/`

Single file [`app_router.dart`](../../lib/src/router/app_router.dart) — a `GoRouter` `Provider` that:

1. Watches `authStateProvider` and `currentUserDocProvider` via a `_AuthListenable` ChangeNotifier that uses a `_routingStateSelector` so it only refreshes on routing-relevant changes (UID, doc loading, needsOnboarding, appIntroSeen).
2. Redirects to `/login`, `/otp`, `/onboarding`, `/app-intro`, or `/home` based on auth + user-doc state.
3. Top-level routes: `/splash`, `/login`, `/signup`, `/forgot-password`, `/otp`, `/onboarding`, `/app-intro`, `/home`, `/language`, `/admin`. Everything past `/home` is opened via `Navigator.push` rather than declarative routes (legacy `MaterialPageRoute` style).

### `theme/`

[`app_theme.dart`](../../lib/src/theme/app_theme.dart) — `AppColors` palette (purple gradient family + accent green/red/orange) and `AppTheme.light` / `AppTheme.dark` constants applied in [`lib/main.dart:299-301`](../../lib/main.dart). Theme mode persisted by `themeModeProvider`.

### `l10n/`

Hand-rolled localization, not codegen ([`lib/src/l10n/`](../../lib/src/l10n)):

- [`app_strings.dart`](../../lib/src/l10n/app_strings.dart) — `AppStrings` class, `context.t.<key>` extension, English fallback for missing keys.
- [`strings_en.dart`](../../lib/src/l10n/strings_en.dart), [`strings_ar.dart`](../../lib/src/l10n/strings_ar.dart), [`strings_ckb.dart`](../../lib/src/l10n/strings_ckb.dart) — `Map<String,String>` translation tables.
- [`ckb_material_localizations.dart`](../../lib/src/l10n/ckb_material_localizations.dart) — custom delegate that maps Kurdish Sorani (`ckb`) onto Arabic Material/Cupertino localizations so RTL widgets behave correctly.

### `navigation/`

[`user_profile_nav.dart`](../../lib/src/navigation/user_profile_nav.dart) — a single `openUserProfile(context, uid: …)` helper that wraps `Navigator.push` to `UserProfileScreen`. Centralized so any "tap a username" call site uses the same route.

### `utils/`

Cross-cutting helpers ([`lib/src/utils/`](../../lib/src/utils)):

- [`responsive.dart`](../../lib/src/utils/responsive.dart) — `Breakpoints` (`xs 320`, `sm 360`, `md 411`, `lg 600`, `xl 840`) and `BuildContext` extensions (`isXSmall`, `isCompact`, `scaleW`, `bottomSafeInset`). Used everywhere instead of hard-coded pixels.
- [`media_cache.dart`](../../lib/src/utils/media_cache.dart) — disk-cache helper for post videos.
- [`app_feedback.dart`](../../lib/src/utils/app_feedback.dart) — toast/snackbar helpers.
- [`maps_links.dart`](../../lib/src/utils/maps_links.dart) — builds Google/Apple Maps deep links for event locations.
- [`share_app.dart`](../../lib/src/utils/share_app.dart) — share-sheet helpers.

## Example data flow — "user taps Like on a post"

1. **UI** — `PostCard` widget in [`lib/src/features/widgets/post_card.dart`](../../lib/src/features/widgets/post_card.dart) renders the like button. On tap, the widget calls `ref.read(postServiceProvider).toggleLike(postId)` (no separate `likeProvider` for the action; mutations go through the service).
2. **Service** — `PostService.toggleLike` ([`lib/src/services/post_service.dart`](../../lib/src/services/post_service.dart)) writes/deletes the doc at `posts/{postId}/likes/{currentUid}` and increments `likesCount` on the parent post via a transaction. The Firestore rule at [`firestore.rules:292-296`](../../firestore.rules) (`isSelf(uid)` for create, owner-or-admin delete) authorizes the like, and the post-update rule at lines 282-287 explicitly permits `likesCount`-only updates by any signed-in user.
3. **State** — The feed is a `StreamProvider` (`feedProvider`, [`lib/src/providers/post_providers.dart:45`](../../lib/src/providers/post_providers.dart)) subscribed to `streamFeed()`. Firestore's local cache reflects the write immediately, the stream re-emits, Riverpod notifies listeners, and the post card rebuilds with the new like count.
4. **Side effect** — `NotificationService` ([`lib/src/services/notification_service.dart`](../../lib/src/services/notification_service.dart)) writes a `notifications/{authorUid}/items/{...}` doc; the `notifications.ts` Cloud Function fans this out as an FCM push, which the recipient's [`fcm_service.dart`](../../lib/src/services/fcm_service.dart) receives.

## Example data flow — "user opens a chat and starts typing"

1. **UI** — `ChatScreen` ([`lib/src/features/screens/chat_screen.dart`](../../lib/src/features/screens/chat_screen.dart)) calls `ref.read(typingServiceProvider).setTyping(chatId, uid, true)` on text field change.
2. **Service** — `TypingService.setTyping` writes `typing/{chatId}/{uid} = true` in **Realtime Database** (not Firestore) and registers `onDisconnect().remove()` so the indicator clears if the network drops ([`lib/src/services/typing_service.dart:11-24`](../../lib/src/services/typing_service.dart)).
3. **Data** — Authorized by [`database.rules.json:9-16`](../../database.rules.json) (`auth.uid === $uid`).
4. **Other side** — The other participant's `ChatScreen` watches a `Stream<bool>` from `TypingService.listenTyping(chatId, otherUid)` and shows a "typing…" dot.

## Boot sequence

[`lib/main.dart`](../../lib/main.dart):

1. `ErrorReportService.instance.runGuarded` opens a `runZonedGuarded` so async crashes are captured.
2. `WidgetsFlutterBinding.ensureInitialized()`, then `_configureSystemUi` (transparent status/nav bars, edge-to-edge on Android).
3. `dotenv.load('.env')` (non-fatal if missing).
4. `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`.
5. Install `ErrorReportService` global handlers.
6. If `USE_FIREBASE_EMULATOR=true` in `.env`, wire Auth/Firestore/Storage/Functions emulators.
7. Sanity-check `authStateChanges.first` with a 5s timeout (logs if stuck).
8. Load `SharedPreferences`, then `runApp(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]))`.
9. `MyApp` watches `routerProvider`, `themeModeProvider`, `localeProvider`, `adminConfigProvider.minAppVersion` and wraps the router in `_VersionGate` for the force-update flow.

## Related files

- [`lib/main.dart`](../../lib/main.dart)
- [`lib/src/router/app_router.dart`](../../lib/src/router/app_router.dart)
- [`lib/src/providers/auth_providers.dart`](../../lib/src/providers/auth_providers.dart)
- [`lib/src/providers/post_providers.dart`](../../lib/src/providers/post_providers.dart)
- [`lib/src/providers/theme_provider.dart`](../../lib/src/providers/theme_provider.dart)
- [`lib/src/providers/locale_provider.dart`](../../lib/src/providers/locale_provider.dart)
- [`lib/src/services/auth_service.dart`](../../lib/src/services/auth_service.dart)
- [`lib/src/services/post_service.dart`](../../lib/src/services/post_service.dart)
- [`lib/src/services/chat_service.dart`](../../lib/src/services/chat_service.dart)
- [`lib/src/services/storage_service.dart`](../../lib/src/services/storage_service.dart)
- [`lib/src/services/presence_service.dart`](../../lib/src/services/presence_service.dart)
- [`lib/src/services/typing_service.dart`](../../lib/src/services/typing_service.dart)
- [`lib/src/services/fcm_service.dart`](../../lib/src/services/fcm_service.dart)
- [`lib/src/services/error_report_service.dart`](../../lib/src/services/error_report_service.dart)
- [`lib/src/l10n/app_strings.dart`](../../lib/src/l10n/app_strings.dart)
- [`lib/src/utils/responsive.dart`](../../lib/src/utils/responsive.dart)
- [`lib/src/navigation/user_profile_nav.dart`](../../lib/src/navigation/user_profile_nav.dart)
- [`firestore.rules`](../../firestore.rules)
- [`database.rules.json`](../../database.rules.json)
