# COIL — Navigation Flow Reference

This document maps every navigation path in the Flutter app under `frontend/lib/`.
It is organized by layers: the router gate at the top, the bottom-nav shell in the
middle, and each feature screen at the bottom (who pushes it, where it pushes to,
how it pops).

The app uses a **two-layer navigation model**:

1.  `go_router` (declarative) — handles the auth / onboarding gate and a small
    set of "root" destinations.
2.  Imperative `Navigator.push(MaterialPageRoute(...))` — used for every
    sub-screen below the root. Most feature navigation is imperative, not
    declarative.

==============================================================================
LAYER 1 — Router gate (go_router)
==============================================================================

File: `frontend/lib/src/router/app_router.dart`

initialLocation: `/splash`

Declared routes:
- `/splash`           → SplashScreen
- `/login`            → LoginScreen
- `/signup`           → SignupScreen
- `/forgot-password`  → ForgotPasswordScreen
- `/otp`              → OtpScreen (reads `?email=` query param)
- `/onboarding`       → OnboardingScreen
- `/home`             → MainScreen (the bottom-nav shell)
- `/language`         → LanguageScreen
- `/admin`            → AdminDashboardScreen

### Redirect rules (evaluated on every nav + on auth refresh)

The router watches a `_AuthListenable` that re-evaluates redirects when one of
these changes:
- auth loading state
- authenticated user UID
- user-doc loading state
- `needsOnboarding` (computed: doc missing OR `username` empty)

Decision tree:

```
authLoading?                     → stay on current route
user == null?
  in auth flow                   → stay
  else                           → /login
userDoc loading?                 → stay
needsOnboarding (doc missing or username blank)?
  already on /onboarding or /otp → stay
  else                           → /onboarding
fully onboarded?
  on auth flow / /onboarding /
  /splash                        → /home
  else                           → no redirect (stay)
```

Notes:
- The `needsOnboarding` gate is persisted (it reads Firestore), not in-memory.
  A user who signs up and force-quits before completing their profile will
  still land on `/onboarding` on next launch.
- Blacklisted users are caught inside `authStateProvider`, which signs them out;
  the router then sends them to `/login`.
- The router also forces sign-out if the user's Firestore doc transitions from
  present → missing while signed in (handled in `main.dart`, not the router).

### Navigator observer

`ErrorReportNavigatorObserver` is attached so every push/pop records the active
screen name into crash reports.

==============================================================================
LAYER 2 — MainScreen bottom-nav shell
==============================================================================

File: `frontend/lib/src/features/model/main_screen.dart`

`/home` resolves to `MainScreen`, which is a `PageView` with **5 tabs**:

| index | tab        | body widget                             |
|-------|------------|-----------------------------------------|
| 0     | Home       | `HomeBody` (in `home_screen.dart`)      |
| 1     | Events     | `EventBody` (in `event_screen.dart`)    |
| 2     | Translate  | `TranslateBody`                         |
| 3     | Messages   | `MessageBody` (in `message_screen.dart`)|
| 4     | Profile    | `ProfileScreen`                         |

Key behaviors:
- The `PageView` has `NeverScrollableScrollPhysics` — tabs only switch via the
  floating bottom-nav, never via swipe.
- Tapping the Home tab while already on Home scrolls the feed to top AND
  invalidates `feedProvider` (pull-to-refresh equivalent).
- Tapping another tab calls `_pageController.jumpToPage(index)` (no animation).
- The Messages tab shows a red unread-dot when `inboxProvider` reports unread
  conversations.
- Every tab switch fires `ErrorReportService.instance.setCurrentScreen(...)`
  so crashes record the active tab.
- Tabs are **not** independent Navigators — pushing from any tab pushes onto
  the root navigator, so the floating bottom-nav is hidden by sub-screens.

==============================================================================
LAYER 3 — Auth / onboarding screens
==============================================================================

### SplashScreen  (`auth/splash_screen.dart`)
- Entered by: cold boot (`initialLocation: '/splash'`).
- Leaves via: router redirect once `authStateProvider` resolves
  → `/login` or `/onboarding` or `/home`.
- No manual navigation. No back button.

### LoginScreen  (`auth/login_screen.dart`)
- Entered by: router redirect when `user == null`.
- Pushes to:
  - `/signup`           (sign-up link)
  - `/forgot-password`  (forgot password link)
- On successful login: router redirect fires → `/home` (or `/onboarding` if
  the user doc still has a null username).
- No back button (root of unauthenticated stack).

### SignupScreen  (`auth/signup_screen.dart`)
- Entered by: LoginScreen.
- On successful sign-up: navigates to `/otp?email=...`.
- Back: `context.go('/login')` (uses go_router, not pop).

### OtpScreen  (`auth/otp_screen.dart`)
- Entered by: `/otp` from SignupScreen. Reads `email` from query params.
- On verify success: profile doc lacks username → router redirects to
  `/onboarding`.
- Back: `context.pop()`.

### ForgotPasswordScreen  (`auth/forgot_password_screen.dart`)
- Entered by: LoginScreen.
- After sending reset email: stays on the screen with a confirmation banner.
- Back: `Navigator.pop()`.

### OnboardingScreen  (`auth/onboarding_screen.dart`)
- Entered by: router redirect when user-doc has no username.
- On submit: writes username to Firestore → `_routingStateSelector` fires →
  router redirects to `/home` automatically.
- No manual nav; no back button (gate cannot be bypassed).

==============================================================================
LAYER 4 — Tab root screens
==============================================================================

### HomeBody  (`home_screen.dart`)  — tab 0
Pushes to:
- `NotificationScreen`         (bell icon)
- `CreatePostScreen`           (+ button)
- `PostDetailScreen`           (post card body)
- `QaThreadScreen`             (Q&A posts)
- `StoryViewerScreen`          (story ring tap)
- `CommentScreen`              (comment icon shortcut)
- `openUserProfile(uid)`       (avatar / username tap)
- `AddToStoryScreen` / `CameraStoryScreen` (story ring "+")

### EventBody  (`event_screen.dart`)  — tab 1
Pushes to:
- `EventDetailScreen`          (event card tap)
- `EventChatScreen`            (group-chat shortcut from an event)
- `openUserProfile(uid)`       (organizer avatar)

### TranslateBody  (`translate_screen.dart`)  — tab 2
Pushes to:
- `SavedTranslationsScreen`    (history icon)

No deeper nav — translation runs inline.

### MessageBody  (`message_screen.dart`)  — tab 3
Pushes to:
- `ChatScreen`                 (1:1 conversation tile)
- `EventChatScreen`            (event group tile)
- `RequestScreen`              ("hidden requests" link)
- `openUserProfile(uid)`       (avatar long-press)

### ProfileScreen  (`profile_screen.dart`)  — tab 4
Pushes to:
- `EditProfileScreen`          (edit button)
- `ProfileSettingsScreen`      (settings gear)
- `QaThreadScreen`             (own Q&A tab)
- `PostDetailScreen`           (own posts grid)
- `openUserProfile(uid)`       (followers / following lists)

Modal sheets used (not nav, but worth noting):
- Bottom sheet for "share profile" / image picker.

==============================================================================
LAYER 5 — Feature sub-screens
==============================================================================

### PostDetailScreen  (`post_detail_screen.dart`)
- Pushed by: HomeBody, NotificationScreen, FCM deep link (rare path), the
  search/feed-equivalent surfaces in ProfileScreen and UserProfileScreen.
- Auto-opens `CommentScreen` on entry if `highlightCommentId` is set.
- Pushes to: `CommentScreen`, `ImageViewerScreen` (media tap),
  `openUserProfile(uid)`.
- Back: implicit AppBar back → `Navigator.pop()`.

### CommentScreen  (`comment_screen.dart`)
- Pushed by: HomeBody (comment shortcut), PostDetailScreen, QaThreadScreen,
  NotificationScreen.
- Pushes to: nothing deeper — replies are inline. Avatars use
  `openUserProfile(uid)`.

### QaThreadScreen  (`qa_thread_screen.dart`)
- Pushed by: HomeBody, ProfileScreen, UserProfileScreen, NotificationScreen.
- Pushes to: `CommentScreen` (answers), `openUserProfile(uid)`.

### StoryViewerScreen  (`story_viewer_screen.dart`)
- Pushed by: HomeBody (story rail), `story_section.dart` widget, the story
  preview path after upload.
- Pushes to: `PostDetailScreen` (cross-linked post in a story),
  `openUserProfile(uid)`. Swiping down or tapping outside pops back.

### CreatePostScreen  (`create_post_screen.dart`)
- Pushed by: HomeBody (+ button), and the AddToStoryScreen flow.
- Pops on success/cancel back to caller.

### AddToStoryScreen  (`add_to_story_screen.dart`)
- Pushed by: HomeBody (story rail "+"), ProfileScreen.
- Pushes to: `CameraStoryScreen`, `CreatePostScreen`.

### CameraStoryScreen  (`camera_story_screen.dart`)
- Pushed by: AddToStoryScreen / CreatePostScreen.
- Pushes to: `VideoStoryPreviewScreen` for captured video.
- Pops back on cancel.

### VideoStoryPreviewScreen  (`video_story_preview_screen.dart`)
- Pushed by: CameraStoryScreen.
- On upload-complete: `Navigator.pop()` (back to camera, which itself pops).

### NotificationScreen  (`notification_screen.dart`)
- Pushed by: HomeBody (bell icon).
- Pushes to (per notification type):
  - new post / like / comment → `PostDetailScreen`
  - new Q&A reply             → `QaThreadScreen`
  - new chat message          → `ChatScreen` or `EventChatScreen`
  - new follower / mention    → `openUserProfile(uid)` / `UserProfileScreen`
  - new event                 → `EventDetailScreen`

### ChatScreen  (`chat_screen.dart`)
- Pushed by: MessageBody (conversation tile), NotificationScreen, RequestScreen,
  UserProfileScreen ("Message" button).
- Pushes to:
  - `openUserProfile(uid)`       (avatar / header)
  - `ChatMediaScreen`            (header media icon)
  - `GroupSettingsScreen`        (header info icon — only for groups)
  - `ImageViewerScreen`          (image bubble tap)

### EventChatScreen  (`event_chat_screen.dart`)
- Pushed by: EventBody, MessageBody (event inbox row), NotificationScreen.
- Pushes to:
  - `openUserProfile(uid)`
  - `EventGroupSettingsScreen`   (header info icon)
  - `ImageViewerScreen`

### ChatMediaScreen  (`chat_media_screen.dart`)
- Pushed by: ChatScreen (info icon → "Media").
- Pushes to: `ImageViewerScreen` for full-screen view. File downloads go
  through `OpenFilex`, not navigation.

### ImageViewerScreen  (`image_viewer_screen.dart`)
- Pushed by: ChatMediaScreen, PostDetailScreen, StoryViewerScreen,
  ChatScreen / EventChatScreen image bubbles.
- Leaf screen — no outward navigation.

### GroupSettingsScreen  (`group_settings_screen.dart`)
- Pushed by: ChatScreen (group info button).
- Pushes to: `openUserProfile(uid)` (member rows). On "Leave / Delete":
  `Navigator.pop()` back to MessageBody.

### EventGroupSettingsScreen  (`event_group_settings_screen.dart`)
- Pushed by: EventChatScreen.
- Pushes to: `openUserProfile(uid)`.

### RequestScreen  (`request_screen.dart`) — Hidden Requests
- Pushed by: MessageBody ("hidden requests" link).
- Pushes to: `ChatScreen` (accept request), `openUserProfile(uid)`.

### UserProfileScreen  (`user_screen.dart`)
- Pushed exclusively via the **`openUserProfile()` helper** in
  `frontend/lib/src/navigation/user_profile_nav.dart`:
  ```dart
  Future<T?> openUserProfile<T>(BuildContext context, {required String uid})
    → Navigator.push(MaterialPageRoute(builder: (_) => UserProfileScreen(uid: uid)))
  ```
  Helper callers (every avatar / username tap in the app):
  EventBody, ChatScreen, EventChatScreen, CommentScreen, QaThreadScreen,
  PostDetailScreen, NotificationScreen, ProfileScreen, MessageBody,
  RequestScreen, GroupSettingsScreen, EventGroupSettingsScreen,
  ProfileVisitorsScreen, ContactUsScreen, StoryViewerScreen, …
- Pushes to: `ChatScreen` (Message button), `openUserProfile()` recursively
  (followers / following lists), `PostDetailScreen` (post grid),
  `QaThreadScreen` (Q&A tab).

### EditProfileScreen  (`edit_profile.dart`)
- Pushed by: ProfileScreen.
- Pops on save/cancel.

### ProfileSettingsScreen  (`profile_settings_screen.dart`)
- Pushed by: ProfileScreen (settings gear).
- Pushes to:
  - `ChangePasswordScreen`
  - `LanguageScreen` (also reachable directly at `/language`)
  - `ContactUsScreen`
  - `SavedTranslationsScreen`
  - `ProfileVisitorsScreen`
  - `AdminDashboardScreen` (only if `isAdmin` — uses `context.go('/admin')`)

### ChangePasswordScreen  (`change_password_screen.dart`)
- Pushed by: ProfileSettingsScreen.
- Returns a `bool` via `Navigator.pop(context, true|false)` so the caller can
  show a snackbar.

### LanguageScreen  (`language_screen.dart`)
- Reached two ways:
  - `/language` route (rare — used by deep links).
  - Pushed from ProfileSettingsScreen.
- Sets locale on `localeProvider`. No further nav.

### ContactUsScreen  (`contact_us_screen.dart`)
- Pushed by: ProfileSettingsScreen.
- Pushes to: `openUserProfile(uid)` for admin contacts.

### SavedTranslationsScreen  (`saved_translations_screen.dart`)
- Pushed by: ProfileSettingsScreen, TranslateBody.
- Returns a selected translation via `Navigator.pop(context, value)` so the
  caller can restore it into the translate UI.

### ProfileVisitorsScreen  (`profile_visitors_screen.dart`)
- Pushed by: ProfileSettingsScreen.
- Pushes to: `openUserProfile(uid)`.

### EventDetailScreen  (`features/widgets/event_detail.dart`)
- Pushed by: EventBody (event card tap) AND by `main.dart` for FCM deep links
  (see Layer 6 below). NOT a `GoRoute` — pure `MaterialPageRoute`.
- If the event has been deleted by the time the FCM tap arrives,
  `EventUnavailableScreen` is pushed instead.

==============================================================================
LAYER 6 — Admin area
==============================================================================

Entry: `context.go('/admin')` from ProfileSettingsScreen (only when the user
is admin; admin gating is enforced server-side too).

### AdminDashboardScreen  (`admin/admin_dashboard_screen.dart`)
Push-targets (all via `Navigator.push`):
- `AdminUsersScreen`            — user list / moderation
- `AdminPostsScreen`            — flagged posts
- `AdminDiscussPostsScreen`     — Q&A moderation
- `AdminEventsScreen`           — event CRUD
- `AdminReportsScreen`          — reports inbox (toolbar tabs: posts, users,
  discuss, errors)
- `AdminPostReportsScreen`      — drill-in from AdminReportsScreen
- `AdminUserReportsScreen`      — drill-in from AdminReportsScreen
- `AdminDiscussReportsScreen`   — drill-in from AdminReportsScreen
- `AdminErrorReportsScreen`     — drill-in from AdminReportsScreen
- `AdminContactRequestsScreen`  — contact requests inbox
- `AdminBlacklistScreen`        — blocked-user management
- `AdminSettingsScreen`         — app-wide settings (incl. `minAppVersion`,
  which feeds the `_VersionGate` in main.dart)

Each admin sub-screen pops back to the dashboard. AdminDashboardScreen back-
press exits via `context.pop()` or `context.go('/home')` depending on the
provider state.

==============================================================================
LAYER 7 — FCM deep links and external navigation
==============================================================================

File: `frontend/lib/main.dart`  (in `_MyAppState`)

1.  `_fcmTapSubscription = FcmService().events.listen(_handleFcmEvent)`
2.  When the user taps a notification that opens the app:
    - `event.openedApp == true` → handled
    - Each `messageId` is processed once (de-dup via `_handledFcmMessageIds`)
3.  Currently the only deep link handled here is `type == 'new_event'`:
    - Reads the event doc from Firestore.
    - If the doc is gone → push `EventUnavailableScreen`.
    - Otherwise → push `EventDetailScreen` with the full event payload.

All other FCM types (chat, comment, follow, etc.) are routed through
`NotificationScreen` — they update badges but don't pop a screen directly.

==============================================================================
LAYER 8 — Version gate
==============================================================================

`_VersionGate` (in `main.dart`) is wrapped around the router's `child`. When
the installed app version is below `adminConfig.minAppVersion`, it overlays an
`_UpdateRequiredScreen` on top of whatever the router rendered. The router
itself keeps running underneath, but the user can't interact with it. This is
not "navigation" per se — it's a blocking overlay — but it's the only way the
user can be on a route they didn't navigate to themselves.

==============================================================================
APPENDIX A — Centralized helpers
==============================================================================

- **`openUserProfile(context, uid: ...)`**
  `frontend/lib/src/navigation/user_profile_nav.dart`. The single entry point
  for opening another user's profile. Always use this rather than constructing
  `UserProfileScreen` directly — keeps deep-link / analytics behavior
  consistent.

- **`ErrorReportNavigatorObserver`**
  Installed in `app_router.dart` as `observers: [ErrorReportNavigatorObserver()]`.
  Records the current route name so crash reports point at the right screen.

- **`ErrorReportService.instance.setCurrentScreen(name)`**
  Called from `MainScreen._trackTab(...)` on every tab change because the
  PageView swap doesn't fire navigator events.

==============================================================================
APPENDIX B — Push vs. go usage (when to use which)
==============================================================================

- Use `context.go('/path')` ONLY for the routes declared in `app_router.dart`:
  splash, login, signup, forgot-password, otp, onboarding, home, language,
  admin. These represent app-level mode changes (auth → home, profile → admin,
  etc.).
- Use `Navigator.push(MaterialPageRoute(...))` for every other screen — they
  are children of the current root and don't change app mode.
- Use `context.pop()` / `Navigator.pop()` to return one level. For
  multi-screen unwinds the router redirect is preferred over `popUntil`
  because it survives state restoration.

==============================================================================
APPENDIX C — Forced redirects (user has no control)
==============================================================================

The user is moved automatically (without tapping anything) in these cases:

1. Auth state changes (sign in / out) → router redirect.
2. User doc disappears while signed in → `authService.signOut()` from
   `main.dart`, which triggers redirect → `/login`.
3. User is blacklisted → `authStateProvider` signs them out → `/login`.
4. User completes onboarding (writes `username`) → redirect → `/home`.
5. Installed version < `minAppVersion` → `_UpdateRequiredScreen` overlay (not a
   route swap, but functionally a blocker).
6. FCM tap with `type == 'new_event'` while app is opening → push
   `EventDetailScreen` (or `EventUnavailableScreen`) on top of `/home`.
