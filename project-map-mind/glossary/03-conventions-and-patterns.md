# Conventions and recurring patterns

A catalog of the patterns this codebase reaches for again and again. New code should follow these to stay consistent.

---

## Riverpod: `ref.watch` vs `ref.read` vs `ref.listen`

| Use | Tool | Why |
| --- | --- | --- |
| **Reactive read in `build`** | `ref.watch(xxxProvider)` | Rebuilds the widget when the value changes. The default for any provider that drives the UI. |
| **One-off read inside a callback or `initState`** | `ref.read(xxxProvider)` | No subscription, so taps and async handlers don't accidentally rebuild. |
| **Side-effect on change** | `ref.listen<AsyncValue<T>>(xxxProvider, (prev, next) { … })` | For things that aren't in the tree: navigation, snackbars, FCM init, marking offline on sign-out. `main.dart` uses this for `authStateProvider` (init FCM, presence, message-cache wipe) and for `currentUserDocProvider` (sign-out when profile disappears). |
| **Force restart of a stream / future** | `ref.invalidate(xxxProvider)` | Used in `MainScreen._onNavTap` to refresh the home feed when the user re-taps Home while already on it. |
| **Subscribe to a slice** | `ref.watch(authStateProvider.select((a) => a.value?.uid))` | Avoids restarting downstream streams on every transient re-emission (token refresh, etc.). Used heavily in `post_providers.dart` and `auth_providers.dart`. |

### Widget base classes

- `ConsumerWidget` — stateless screen/widget with `Widget build(BuildContext context, WidgetRef ref)`.
- `ConsumerStatefulWidget` + `ConsumerState<T>` — stateful screen/widget; `ref` is on `this`. Used wherever a `_XxxState` carries controllers, animation tickers, or `WidgetsBindingObserver`.

---

## Async pattern: `AsyncValue<T>.when(...)`

`AsyncValue.when` is used for screens whose primary content depends on an async stream/future:

```dart
ref.watch(usersAsync).when(
  loading: () => const Center(child: CircularProgressIndicator()),
  error: (e, _) => Text('Error: $e'),
  data: (users) => ListView(...),
);
```

For non-blocking sidecars (badge counts, optional widgets), the codebase often uses `.valueOrNull ?? <fallback>` instead — e.g. `ref.watch(inboxProvider).valueOrNull ?? const <ChatConversation>[]` in `MainScreen`. The pattern is "block the screen when the data is the screen's reason for existing; degrade silently when it's a sidecar".

---

## Optimistic updates

Likes, follows, saves, and reposts update local state immediately, then await the Firestore write. The canonical implementation is in `post_card.dart`:

```dart
Future<void> _toggleLike() async {
  final currentLiked = ref.read(isLikedProvider(widget.post.id)).value ?? false;
  if (_pendingLike != null) return; // already in-flight
  setState(() => _pendingLike = !currentLiked);
  try {
    await ref.read(postServiceProvider).toggleLike(widget.post.id);
  } finally {
    if (mounted) setState(() => _pendingLike = null);
  }
}
```

The UI reads "use `_pendingLike` if non-null, otherwise the stream value" so the icon flips instantly and the count derives from the same optimistic value. The `if (_pendingLike != null) return` guard short-circuits rapid double-taps. Double-tap-to-like in `_likeFromDoubleTap` always *likes* (never unlikes), playing a heart-burst animation as confirmation.

The same pattern, manually written, appears in `lib/src/features/screens/user_screen.dart` for follow toggles ("Optimistic local update (instant)").

---

## Error reporting

`ErrorReportService` (`lib/src/services/error_report_service.dart`) is a singleton that captures errors into the Firestore `errorReports/` collection.

- The entire `main()` body runs inside `ErrorReportService.instance.runGuarded(() async { … })` so the `WidgetsFlutterBinding`, Firebase init, and `runApp` all share one zone (Flutter asserts this) and async errors thrown from timers / futures are caught.
- `ErrorReportService.instance.install()` is called *after* Firebase init. It hooks `FlutterError.onError` (framework errors) and `PlatformDispatcher.instance.onError` (platform errors).
- Writes are rate-limited (25/session, 3s minimum gap, signature dedupe) and tag each report with the current screen name (updated by `ErrorReportNavigatorObserver` and `setCurrentScreen` — `MainScreen` calls it on every tab change with `'Home'` / `'Events'` / `'Translate'` / `'Messages'` / `'Profile'`).
- Manual reports use `ErrorReportService.instance.report(error, stack, context: '…', kind: '…')`.

---

## Backend-keys + locale wrapper

Backend stores certain enum-like values in English so the admin dashboard is always readable. The UI translates via a helper in `AppStrings`:

```dart
// Firestore stores the English key:
{'reason': 'Spam or scam'}

// UI renders the translation:
Text(context.t.reportReasonLabel(report.reason))
```

`reportReasonLabel(englishReason)` is a `switch` over the canonical English strings and returns the localized form (`reportReasonSpam`, `reportReasonImpersonation`, …). Unknown values pass through unchanged so unmigrated docs don't crash. See `lib/src/l10n/app_strings.dart` lines 1904–1930.

The same shape applies to other backend-stored English strings (notification `type`, role names like `'admin'`/`'org_admin'`, event funding status). When you add a new backend enum, keep the value English on the doc and add a translation helper on `AppStrings`.

---

## `AppGlassCard` / `AppPageBackground`

Almost every screen uses the same two shared widgets to get the "blurred gradient" look:

| Widget | Purpose |
| --- | --- |
| `AppPageBackground` | A `Stack` with a 3-stop gradient (different for light/dark) + three positioned `_AmbientGlow` radial gradients. Wraps the entire body. |
| `AppGlassCard` | A glass-morphism card: `BackdropFilter` blur + translucent surface + thin white border + soft shadow. Configurable `radius`, `surfaceAlpha`, `borderAlpha`, optional purple-tinted `emphasize` shadow. |

Both live in `lib/src/features/widgets/app_page_background.dart`. Use `AppGlassCard` for tiles, panels, sheets, and chips that should look like the bottom nav.

---

## System UI overlay (AppBar over background)

To keep the AppBar from clipping a chunk out of the gradient, every screen with a custom background uses this AppBar shape (`AdminDashboardScreen` is the canonical example):

```dart
Scaffold(
  backgroundColor: Colors.transparent,
  appBar: AppBar(
    title: Text(context.t.adminDashboardTitle),
    backgroundColor: Colors.transparent,
    foregroundColor: context.textPrimary,
    elevation: 0,
    flexibleSpace: const AppPageBackground(child: SizedBox.expand()),
  ),
  body: AppPageBackground(
    child: ListView(...),
  ),
);
```

Both the body and the AppBar paint the same `AppPageBackground` so the gradient continues edge-to-edge under the status bar. Found in ~21 screens (search: `flexibleSpace: const AppPageBackground`).

For status-bar icon brightness, `MaterialApp.builder` sets `SystemUiOverlayStyle` per theme on every rebuild — see `lib/main.dart` lines 321–331. On lifecycle `resumed`, `_configureSystemUi(appBrightness: …)` is re-called to fix a flash on dark-mode resume.

---

## The `_VersionGate` pattern (forced updates)

In `lib/main.dart`:

```dart
return MaterialApp.router(
  ...,
  builder: (context, child) {
    ...
    return ResponsiveBootstrap(
      child: GestureDetector(
        ...,
        child: _VersionGate(
          minVersion: minVersion,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  },
);
```

`_VersionGate`:

- Reads the running version once via `PackageInfo.fromPlatform()`.
- Compares it against `AdminConfig.minAppVersion` (from `adminConfigProvider`) using `_compareVersions` (numeric segment compare, non-numeric chars stripped).
- If `current < minVersion`, renders the normal `widget.child` *behind* a full-screen `_UpdateRequiredScreen` overlay so the app is visually blocked but state stays alive (useful if the admin lowers the gate while the app is open).
- Fails open: if `_currentVersion` is null or `minVersion` is empty, the app runs normally.

---

## Lifecycle observer for video players (codec teardown)

Android releases the video codec's output surface when the activity is backgrounded; `VideoPlayerController` still reports `isInitialized == true` on resume but renders a black frame. Pattern (canonical implementation: `_VideoStoryView` in `lib/src/features/screens/story_viewer_screen.dart` lines 2506–2533):

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  // Deliberately NOT reacting to inactive / hidden — those fire on
  // transient focus loss (notification shade, permission dialogs,
  // transient overlays) and tearing down was overly aggressive.
  if (state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached) {
    final c = _controller;
    if (c != null && c.value.isInitialized) {
      _lastKnownPosition = c.value.position;
    }
    _stopPositionTimer();
    _controller?.removeListener(_onTick);
    unawaited(_controller?.dispose() ?? Future.value());
    _controller = null;
    if (mounted) setState(() => _suspended = true);
  } else if (state == AppLifecycleState.resumed && _suspended) {
    unawaited(_setup(resumeFrom: _lastKnownPosition));
  }
}
```

Rules:

- React to **`paused`** and **`detached`** only. Skip `inactive` and `hidden`.
- Remember the playhead before disposing so resume rebuilds from the same spot.
- A separate `_setupInFlight` guard prevents overlapping `initialize()` calls when lifecycle events race.
- Story progress is driven by a periodic position timer (`Timer.periodic(~60ms)`) — `VideoPlayerController.addListener` only fires on coarse state changes, which makes the progress bar tick jerkily.

The same pattern (minus the timer) is used in `camera_story_screen.dart` for `CameraController` — though that file *does* tear down on `inactive` (camera surfaces are more fragile and Android can revoke them silently). `video_story_preview_screen.dart` only pauses on `inactive`/`paused` rather than disposing.

---

## Snackbars via `AppFeedback`

Never call `ScaffoldMessenger.showSnackBar` directly. Use:

```dart
AppFeedback.showSuccess(context, context.t.postPublished);
AppFeedback.showInfo(context, context.t.someInfo);
AppFeedback.showError(context, context.t.errorGeneric);
```

This gives a consistent themed pill snackbar (purple/dark/red, rounded, icon, bold text). The wrapper also calls `clearSnackBars()` before showing the new one so toasts don't stack.

If a screen pops itself before the snackbar should show, capture `ScaffoldMessenger.of(context)` *before* popping and use the `…On` variants:

```dart
final messenger = ScaffoldMessenger.of(context);
Navigator.of(context).pop();
AppFeedback.showSuccessOn(messenger, 'Saved');
```

See `lib/src/utils/app_feedback.dart`.

The `PoppingActionIcon` in the same file is the matching visual confirmation for save / bookmark / repost taps — a small scale-pulse on toggle.

---

## Presence and typing (RTDB, not Firestore)

These two pieces of state are in Firebase Realtime Database (paths `presence/{uid}` and `typing/{chatId}/{uid}`) because RTDB's `onDisconnect` semantics give us free auto-cleanup when a socket drops. The Firestore equivalents would leak stale online/typing flags.

```dart
await ref.set(true);
await ref.onDisconnect().remove();   // typing
await ref.onDisconnect().update({...}); // presence
```

`PresenceService.setOnline` is called on sign-in (in the `authStateProvider` listener in `main.dart`) and on app `resumed`. `setOffline` is called on sign-out *and* on any lifecycle transition out of `resumed` (paused / inactive / detached / hidden) — being explicit means peers see you go offline immediately rather than after the socket times out.

---

## Singleton accessors and lazy Firebase

Singletons use the `Xxx.instance` pattern: `ErrorReportService.instance`, `MessageCache.instance`, `FcmService()` (the class itself is single-use and the static `_eventsController` is shared, but it's instantiated freely).

Anything that may be touched *before* Firebase has initialized must lazily resolve the Firestore handle. `ErrorReportService` shows the pattern:

```dart
FirebaseFirestore? get _db {
  if (_dbInstance != null) return _dbInstance;
  if (Firebase.apps.isEmpty) return null;
  return _dbInstance = FirebaseFirestore.instance;
}
```

This avoids the "FirebaseAuth.instance called before Firebase.initializeApp" boot crash.

---

## Auth-token settle (race fix)

Firestore streams opened *immediately* after `signInWithCredential` produce a transient `permission-denied` because the SDK hasn't yet processed the new auth token. `authStateProvider` defends against this:

```dart
authService.authStateChanges.asyncMap((user) async {
  if (user != null) {
    await user.getIdToken();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return user;
});
```

And downstream streams use a retry helper (`_retryStream` in `auth_providers.dart`) that re-subscribes up to 3 times with backoff (`600ms`, `1.2s`, `1.8s`) on error.

---

## Combining streams with rxdart

When a screen's data depends on multiple Firestore streams (the feed needs posts + following set + blocked set), the code uses `Rx.combineLatest3` from `package:rxdart`:

```dart
return Rx.combineLatest3(
  postService.streamFeed().onErrorReturn(<Post>[]),
  followService.getFollowing(uid).onErrorReturn(<String>[]),
  blockService.getBlockedUsers(uid).onErrorReturn(<String>[]),
  (List<Post> posts, List<String> following, List<String> blocked) {
    ...
  },
);
```

`onErrorReturn(<T>[])` is used so a transient error on one input degrades to an empty list rather than propagating to the UI's error state. See `lib/src/providers/post_providers.dart`.

---

## Deterministic notification doc ids

To prevent `like → unlike → like` from creating duplicate notifications, like/repost notifications use an explicit `docId` built from `actor + type + target`:

```dart
final notifId = 'repost_${user.uid}_$postId';
await _notifications.upsertNotification(
  docId: notifId,
  targetUid: postOwnerUid,
  type: 'repost',
  actorUid: user.uid,
  targetId: postId,
);
```

`removeNotificationById` cleans up on un-toggle. See `lib/src/services/notification_service.dart` (`upsertNotification`, `removeNotificationById`).

---

## Related files

- `lib/main.dart`
- `lib/src/features/widgets/app_page_background.dart`, `post_card.dart`
- `lib/src/features/screens/story_viewer_screen.dart`, `camera_story_screen.dart`, `video_story_preview_screen.dart`
- `lib/src/features/screens/admin/admin_dashboard_screen.dart`, `admin_users_screen.dart`
- `lib/src/providers/auth_providers.dart`, `post_providers.dart`, `admin_providers.dart`, `notification_providers.dart`
- `lib/src/services/error_report_service.dart`, `presence_service.dart`, `typing_service.dart`, `notification_service.dart`, `post_service.dart`, `fcm_service.dart`
- `lib/src/utils/app_feedback.dart`
- `lib/src/l10n/app_strings.dart`
- `lib/src/theme/app_theme.dart`
