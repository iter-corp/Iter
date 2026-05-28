# Router & Navigation

App-wide navigation infrastructure for the Iter (COIL) Flutter app. Single `GoRouter` instance with a centralized `redirect` callback gates the entire app behind the auth + onboarding + app-intro state machine. Feature screens that aren't part of the gate (user profiles, event details, settings, chat) are pushed imperatively via `Navigator.push`.

## Router library

- **GoRouter** (`go_router` package). One global instance exposed as [`routerProvider`](../../lib/src/router/app_router.dart). Consumed by `MaterialApp.router` in [`main.dart`](../../lib/main.dart).
- Initial location: `/splash`.
- Observers: `[ErrorReportNavigatorObserver()]` — feeds the current screen name to [`ErrorReportService`](../../lib/src/services/error_report_service.dart) so every error report includes which screen the user was on.
- `refreshListenable`: `_AuthListenable` — a `ChangeNotifier` that wraps a Riverpod `ref.listen` against a tuple selector (`(isAuthLoading, user uid, isUserDocLoading, needsOnboarding, appIntroSeen)`). Only notifies the router when one of those values actually changes, preventing route churn on every token refresh.

## Route table

All routes live in [`lib/src/router/app_router.dart`](../../lib/src/router/app_router.dart).

| Path | Screen | Notes |
|---|---|---|
| `/splash` | `SplashScreen` | Boot route. The redirect later pushes the user off this once auth resolves. |
| `/login` | `LoginScreen` | Public — auth flow. |
| `/signup` | `SignupScreen` | Public — auth flow. |
| `/forgot-password` | `ForgotPasswordScreen` | Public — auth flow. |
| `/otp` | `OtpScreen` | Email verification. Reads `?email=…` query param via `state.uri.queryParameters['email']`. |
| `/onboarding` | `OnboardingScreen` | First-time profile setup (writes a username). |
| `/app-intro` | `AppIntroScreen` | One-time feature walkthrough shown after onboarding, gated by `appIntroSeen` flag on the user doc. |
| `/home` | `MainScreen` | The 5-tab `PageView` shell (Home / Events / Translate / Messages / Profile). |
| `/language` | `LanguageScreen` | Language picker. Reachable from settings; can also be reached pre-auth. |
| `/admin` | `AdminDashboardScreen` | Admin dashboard. Visibility is gated by [`isAdminProvider`](../../lib/src/providers/admin_providers.dart) and `isOrgAdminProvider`; the route itself is open but its screen renders only the sections each role can access. |

## Redirect / auth gate logic

The `redirect` callback in [`app_router.dart`](../../lib/src/router/app_router.dart) runs on every refresh and resolves where the user must be. Order matters:

```
1. authState is loading        → stay on current route (no redirect).
2. user == null                 → redirect to /login (unless already in /login, /signup,
                                  /forgot-password, /otp).
3. user.emailVerified == false  → redirect to /otp?email=<email> (unless already on /otp).
4. currentUserDoc is loading    → stay on current route (so we don't flash /splash).
5. userDoc missing OR
   userDoc.username trim empty → needs onboarding → redirect to /onboarding
                                  (unless already on /onboarding or /otp).
6. appIntroSeen != true         → redirect to /app-intro
                                  (unless already on /app-intro).
7. Otherwise (fully onboarded): → if currently on /splash, any auth-flow route,
                                  /onboarding, or /app-intro, redirect to /home.
                                  Else, no redirect.
```

Key implementation details:

- **Onboarding is checked against the persisted Firestore doc**, NOT the in-memory `AuthService.justSignedUp` flag. A user who signed up then killed the app before completing onboarding still gets sent to `/onboarding` on next launch.
- Signup writes `username: null` to the user doc; onboarding writes the real value. So "doc exists with username == null" is the durable "still needs onboarding" signal.
- The `[Router]` `debugPrint` log lines (e.g. `[Router] loc=$loc uid=… needsOnboarding=… appIntroSeen=…`) trace every redirect decision — useful for diagnosing redirect loops.
- `_AuthListenable` uses `Provider`-based selector (`_routingStateSelector`) to compare only UIDs and bool flags, not the whole `User` object. Without this, every Auth token refresh would notify the router and cause flicker.

## Bottom navigation

The 5-tab bottom nav is rendered **inside** [`MainScreen`](../../lib/src/features/model/main_screen.dart) — it's NOT a separate router shell. Tabs live in a `PageView` controlled by `PageController`, with the floating glass-pill nav bar drawn on top.

There are TWO bottom-nav widgets in the codebase:

- [`BottomNav`](../../lib/src/features/widgets/botton_nav.dart) — a standalone widget (note: filename is misspelled `botton_nav.dart`). Used in older / alternative screens.
- The inline floating nav inside [`MainScreen`](../../lib/src/features/model/main_screen.dart) (current MainScreen) — a `BackdropFilter` + animated white circle bubble that slides between slots.

### Tab → Screen mapping (current MainScreen)

| Tab index | Icon asset | Body widget | File |
|---|---|---|---|
| 0 | `assets/icons/Home.svg` | `HomeBody` | [`home_screen.dart`](../../lib/src/features/screens/home_screen.dart) |
| 1 | `Icons.diversity_3_rounded` (overrides SVG) | `EventBody` | [`event_screen.dart`](../../lib/src/features/screens/event_screen.dart) |
| 2 | `assets/icons/Translate.svg` | `TranslateBody` | [`translate_screen.dart`](../../lib/src/features/screens/translate_screen.dart) |
| 3 | `assets/icons/Message.svg` | `MessageBody` | [`message_screen.dart`](../../lib/src/features/screens/message_screen.dart) |
| 4 | `assets/icons/Profile.svg` | `ProfileScreen` | [`profile_screen.dart`](../../lib/src/features/screens/profile_screen.dart) |

Behaviors worth noting:

- Tapping the Home tab while already on Home scrolls to top AND calls `ref.invalidate(feedProvider)` to refresh the feed.
- Tab 3 (Messages) gets an unread-dot badge driven by `inboxProvider`: the count of conversations with `unreadCount > 0`.
- `_trackTab(index)` calls `ErrorReportService.instance.setCurrentScreen('Home' | 'Events' | 'Translate' | 'Messages' | 'Profile')` so the active tab is attached to any error report.
- `PageView` uses `NeverScrollableScrollPhysics()` — tabs can only switch via taps.
- `AnimatedPositionedDirectional` is used for the white bubble so it tracks correctly in both LTR and RTL.

## Imperative pushes (not router-managed)

Anything below `/home` is pushed via `Navigator.push` with `MaterialPageRoute`. These do NOT have a route path. Examples:

- **User profile**: [`openUserProfile(context, uid: ...)`](../../lib/src/navigation/user_profile_nav.dart) pushes `UserProfileScreen(uid: uid)`. This is the canonical helper — everything that opens another user's profile goes through it.
- **Event detail**: `EventDetailScreen` — pushed from the events list and from FCM tap routing in [`main.dart`](../../lib/main.dart) `_openEventDetailFromPush`.
- **Event unavailable**: `EventUnavailableScreen` — pushed when an FCM `new_event` tap resolves to a missing event doc.
- **Chat screen, comments thread, story viewer, settings sub-screens, admin sub-pages**: all use `Navigator.push(MaterialPageRoute(...))`.

Pattern: anywhere you'd want a tappable user identity → `openUserProfile`. Everywhere else, the calling screen builds its own `MaterialPageRoute` inline.

## FCM tap routing

Push-notification taps are routed inside [`_MyAppState`](../../lib/main.dart):

- `FcmService().events` is a broadcast stream of `FcmMessageEvent { message, openedApp }`.
- `_handleFcmEvent` only acts when `openedApp == true` (notification was tapped, not received in foreground).
- A `_handledFcmMessageIds` `Set<String>` de-dupes — the same `getInitialMessage` is re-emitted across hot restarts.
- Currently the only routed type is `new_event`: it fetches `events/{targetId}` and pushes either `EventDetailScreen` or `EventUnavailableScreen`.

## Version gate

[`_VersionGate`](../../lib/main.dart) wraps the entire app inside `MaterialApp.builder`. Behavior:

- Reads `adminConfig.minAppVersion` via `adminConfigProvider`.
- Reads the installed version via `PackageInfo.fromPlatform()`.
- Compares using a tolerant parser (`_compareVersions`) — splits on `.`, strips non-digits, treats missing components as 0.
- If `current < minVersion`, draws a fullscreen `Stack` overlay (`_UpdateRequiredScreen`) on top of the normal app showing an update-required dialog with `Icons.system_update_outlined` and the translated `context.t.updateRequiredTitle` / `updateRequiredBody(required, current)`.
- **Fails open**: if the config hasn't loaded or the version can't be parsed, the app runs normally.
- Sits OUTSIDE the router but inside `MaterialApp` — it overlays on top of whatever screen the router has surfaced.

## Related files

- [`lib/src/router/app_router.dart`](../../lib/src/router/app_router.dart) — router provider, route table, redirect, `_AuthListenable`.
- [`lib/src/navigation/user_profile_nav.dart`](../../lib/src/navigation/user_profile_nav.dart) — `openUserProfile` helper.
- [`lib/main.dart`](../../lib/main.dart) — `MaterialApp.router` wiring, `_VersionGate`, FCM tap routing.
- [`lib/src/features/model/main_screen.dart`](../../lib/src/features/model/main_screen.dart) — bottom-nav shell + PageView.
- [`lib/src/features/widgets/botton_nav.dart`](../../lib/src/features/widgets/botton_nav.dart) — alternative standalone bottom-nav widget.
- [`lib/src/services/error_report_service.dart`](../../lib/src/services/error_report_service.dart) — `ErrorReportNavigatorObserver` and `setCurrentScreen`.
- [`lib/src/providers/auth_providers.dart`](../../lib/src/providers/auth_providers.dart) — `authStateProvider`, `currentUserDocProvider`.
- [`lib/src/providers/admin_providers.dart`](../../lib/src/providers/admin_providers.dart) — `adminConfigProvider` (drives version gate).
