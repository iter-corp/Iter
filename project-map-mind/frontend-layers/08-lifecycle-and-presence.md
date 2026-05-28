# App Lifecycle & Presence

The app reacts to OS lifecycle transitions in several places. The single most important consumer is the **presence system** (online/offline + lastSeen) backed by Firebase Realtime Database. Other consumers include the status-bar style refresh and ad-hoc teardown in screens like the video story player.

## The app-wide `WidgetsBindingObserver`

[`_MyAppState`](../../lib/main.dart) (`class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver`) is the only app-wide lifecycle observer. It's registered/unregistered with the root binding:

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  _fcmTapSubscription = FcmService().events.listen(_handleFcmEvent);
}

@override
void dispose() {
  _fcmTapSubscription.cancel();
  WidgetsBinding.instance.removeObserver(this);
  super.dispose();
}
```

It overrides `didChangeAppLifecycleState(AppLifecycleState state)`. There are two branches:

### On resume (`AppLifecycleState.resumed`)

```dart
final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
unawaited(_configureSystemUi(
  appBrightness: isDark ? Brightness.dark : Brightness.light,
));

final uid = ref.read(authStateProvider).value?.uid;
if (uid != null) unawaited(_presence.setOnline(uid));
```

Two effects:

1. **Re-apply system-UI overlay style** using the CURRENT theme brightness. Without this, returning to the foreground in dark mode briefly flashed invisible status-bar icons because the previous overlay was applied for light mode at boot.
2. **Restore presence to "online"**. The RTDB `onDisconnect` handler set inside `PresenceService.setOnline` may have already flipped the user back to offline if the socket dropped during background, so we re-register it here too.

### On pause / inactive / detached / hidden

```dart
final uid = ref.read(authStateProvider).value?.uid;
if (uid != null) unawaited(_presence.setOffline(uid));
```

The user is marked offline as soon as the app backgrounds, so other users see the green dot disappear immediately — instead of waiting for the RTDB `onDisconnect` to fire on socket close (which can take a while). This catches the four backgrounded states Flutter exposes.

## The presence system

File: [`lib/src/services/presence_service.dart`](../../lib/src/services/presence_service.dart). Backed by Firebase Realtime Database at path `presence/{uid}`.

### `PresenceData` model

```dart
class PresenceData {
  final bool online;
  final DateTime? lastSeen;

  String get statusText {
    if (online) return 'Online';
    if (lastSeen == null) return '';
    final d = DateTime.now().difference(lastSeen!);
    if (d.inSeconds < 60) return 'last seen just now';
    if (d.inMinutes < 60) return 'last seen ${d.inMinutes}m ago';
    if (d.inHours < 24)   return 'last seen ${d.inHours}h ago';
    return 'last seen ${d.inDays}d ago';
  }
}
```

### `PresenceService` API

| Method | Purpose |
|---|---|
| `Future<void> setOnline(String uid)` | Updates `presence/{uid}` with `{online: true, lastSeen: ServerValue.timestamp}` and **registers the `onDisconnect` handler** `{online: false, lastSeen: ServerValue.timestamp}` so Firebase auto-flips the user offline if the socket drops. |
| `Future<void> setOffline(String uid)` | Explicit write: `{online: false, lastSeen: ServerValue.timestamp}`. Used on background AND signout. |
| `Stream<PresenceData> listenPresence(String uid)` | Live presence for any user; emits `online: false` on null/missing. |

Every method is wrapped in `try {} catch (_) {}` so RTDB not being configured doesn't break the app.

### Where presence is touched

The full lifecycle of the green dot is driven from FOUR places:

| Event | Code path | What happens |
|---|---|---|
| **Sign in** (or session restore) | `ref.listen<AsyncValue<User?>>(authStateProvider, ...)` in [`main.dart`](../../lib/main.dart) `_MyAppState.build` | `_presence.setOnline(nextUser.uid)` so the green dot lights up before the user enters any chat. |
| **Sign out** | Same `ref.listen` block | `_presence.setOffline(previousUser.uid)` so the dot drops the moment they sign out. Also wipes the on-disk message cache (`MessageCache.instance.clearAll()`) and removes the FCM token. |
| **Background** | `didChangeAppLifecycleState(paused\|inactive\|detached\|hidden)` | `_presence.setOffline(uid)`. |
| **Resume** | `didChangeAppLifecycleState(resumed)` | `_presence.setOnline(uid)`. |
| **Socket drop** | RTDB `.onDisconnect()` (set in `setOnline`) | Server-side: auto-flips to `{online: false, lastSeen: timestamp}`. |

## Presence consumption (UI side)

`presenceWatchProvider` ([`chat_providers.dart`](../../lib/src/providers/chat_providers.dart)) wraps `PresenceService.listenPresence` so any UI can show the green dot / last-seen:

```dart
final presenceWatchProvider =
    StreamProvider.family<PresenceData, String>((ref, uid) {
  return ref.watch(presenceServiceProvider).listenPresence(uid);
});
```

Consumers:

- **Inbox tiles** — green dot next to avatar.
- **Chat screen header** — "Online" / "last seen 5m ago".
- **User profile** — small dot on avatar.

## Typing indicator — parallel RTDB pattern

[`typing_service.dart`](../../lib/src/services/typing_service.dart) uses the same RTDB + `onDisconnect` pattern at path `typing/{chatId}/{uid}`:

- `setTyping(chatId, uid, true)` writes the flag and registers `onDisconnect().remove()`.
- `setTyping(chatId, uid, false)` removes it.

This guarantees the "typing…" indicator never gets stuck if the typer's connection drops.

## Other lifecycle hooks (per-screen)

Several screens implement their OWN `WidgetsBindingObserver` for screen-specific teardown — these don't go through `_MyAppState`. The most prominent one is the **video story player**, which uses lifecycle to:

- Pause video playback when the app goes into the background.
- Resume from the same frame on `resumed`.
- Tear down the `VideoPlayerController` when the route is popped to free GPU resources.

Other screens with their own lifecycle observers include the **chat screen** (mark messages seen on resume, cancel typing on pause) and the **story viewer** (pause auto-advance timer).

These screen-level observers are scoped to their `State` and are independent of the app-wide observer in `_MyAppState`.

## Other state listeners in `_MyAppState.build`

Two `ref.listen` blocks complement the lifecycle observer:

### Auth-state listener (login / logout side effects)

```dart
ref.listen<AsyncValue<User?>>(authStateProvider, (prev, next) {
  final previousUser = prev?.value;
  final nextUser = next.value;
  final fcmService = FcmService();

  if (nextUser != null) {
    unawaited(fcmService.init(nextUser.uid));
    unawaited(_presence.setOnline(nextUser.uid));
  } else if (previousUser != null) {
    unawaited(fcmService.removeToken(previousUser.uid));
    unawaited(_presence.setOffline(previousUser.uid));
    unawaited(MessageCache.instance.clearAll());
  }
});
```

So on sign-in: FCM init + presence online. On sign-out: FCM token removal + presence offline + message cache wipe.

### User-doc-deleted listener

Detects an admin deleting the user's Firestore doc on another device:

```dart
ref.listen<AsyncValue<Map<String, dynamic>?>>(currentUserDocProvider, (prev, next) {
  final authed = ref.read(authStateProvider).value != null;
  final wasPresent = prev?.value != null;
  final nowMissing = next.hasValue && next.value == null;
  if (authed && wasPresent && nowMissing) {
    unawaited(ref.read(authServiceProvider).signOut());
  }
});
```

This guards against ghost sessions: if the user is signed in and their `users/{uid}` doc goes from "exists" to "missing" (admin deleted them), they're auto-signed-out. The cross-session admin-delete case (user comes back on a new device) is handled separately via the blacklist check inside `authStateProvider`.

## FCM tap routing — also app-wide

`_MyAppState` also owns `_fcmTapSubscription` = `FcmService().events.listen(_handleFcmEvent)`. See `01-router-and-navigation.md` (FCM tap routing) for details. The subscription is cancelled in `dispose()` so the listener doesn't outlive the app.

## Related files

- [`lib/main.dart`](../../lib/main.dart) — `_MyAppState`, `didChangeAppLifecycleState`, auth & user-doc listeners, FCM tap subscription.
- [`lib/src/services/presence_service.dart`](../../lib/src/services/presence_service.dart) — `PresenceService`, `PresenceData`, RTDB `onDisconnect`.
- [`lib/src/services/typing_service.dart`](../../lib/src/services/typing_service.dart) — sibling RTDB pattern with `onDisconnect`.
- [`lib/src/providers/chat_providers.dart`](../../lib/src/providers/chat_providers.dart) — `presenceWatchProvider`, `typingWatchProvider`.
- [`lib/src/services/message_cache.dart`](../../lib/src/services/message_cache.dart) — `clearAll()` called on signout.
- [`lib/src/services/fcm_service.dart`](../../lib/src/services/fcm_service.dart) — `init(uid)` / `removeToken(uid)` paired with sign-in/out.
- [`lib/src/providers/auth_providers.dart`](../../lib/src/providers/auth_providers.dart) — `authStateProvider`, `currentUserDocProvider`.
