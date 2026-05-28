# Flow 14 — App background / resume lifecycle

When the user backgrounds the app, several systems must release resources and mark the user offline. When the app comes back to the foreground, those systems re-arm.

## Sequence

```mermaid
sequenceDiagram
  participant U as User
  participant Sys as OS
  participant App as _MyAppState (WidgetsBindingObserver)
  participant Presence as PresenceService
  participant RTDB as Realtime Database
  participant Story as Active StoryVideoPlayer
  participant SysUi as SystemChrome

  U->>Sys: presses Home / switches apps
  Sys->>App: AppLifecycleState.paused (also inactive/detached/hidden)
  App->>Presence: setOffline(uid)
  Presence->>RTDB: presence/{uid}.update({online:false, lastSeen})
  par video stories tear down
    Story->>Story: VideoPlayerController.dispose<br/>(state._suspended = true)
  end
  Note over App: Firestore listeners auto-pause when SDK detects backgrounding
  U->>Sys: returns to app
  Sys->>App: AppLifecycleState.resumed
  App->>SysUi: _configureSystemUi(appBrightness: current themeMode brightness)
  SysUi->>SysUi: SystemUiOverlayStyle (status bar icons re-applied)
  App->>Presence: setOnline(uid)
  Presence->>RTDB: presence/{uid}.update({online:true, lastSeen}); onDisconnect re-registered
  Story->>Story: build new VideoPlayerController + initialize + seek<br/>(if _suspended was true)
```

## Numbered steps

### On pause

1. **OS signals lifecycle change.** Flutter dispatches `didChangeAppLifecycleState` with one of `paused`, `inactive`, `detached`, `hidden`. [`_MyAppState`](../../lib/main.dart) (lines 172–198) treats all four as "going offline":

   ```dart
   final uid = ref.read(authStateProvider).value?.uid;
   if (uid != null) unawaited(_presence.setOffline(uid));
   ```

2. **PresenceService.setOffline** ([`presence_service.dart`](../../lib/src/services/presence_service.dart) lines 50–57):
   ```
   presence/{uid}.update({online: false, lastSeen: ServerValue.timestamp})
   ```
   This fires immediately rather than waiting for the RTDB socket's `onDisconnect` to fire — the rest of the app sees the user as offline within milliseconds.

3. **Active video stories tear down.** If the user happens to have a `StoryViewerScreen` open with a video playing, [`story_viewer_screen.dart` lines 2507–2538](../../lib/src/features/screens/story_viewer_screen.dart):
   ```dart
   if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
     _suspended = true;
     _controller?.pause();
     _controller?.dispose();
     _controller = null;
   }
   ```
   The video element relinquishes the codec — on Android in particular, holding the codec across the background → background transition has caused playback failures.

4. **Firestore listeners.** The Firestore SDK detects the background state and pauses snapshot listeners internally (no client code needed). They resume on `resumed`.

5. **Typing indicator.** If a chat is open with the input focused, the typing flag remains `true` in RTDB. The `onDisconnect().remove()` registered in [`TypingService.setTyping`](../../lib/src/services/typing_service.dart) cleans it up when the socket actually drops. There's no explicit "background → typing off" hook.

### On resume

6. **OS signals `AppLifecycleState.resumed`.** Three things happen in `_MyAppState.didChangeAppLifecycleState` (lines 173–187):

   - **Status bar overlay re-apply.** Reads the current theme mode and calls `_configureSystemUi(appBrightness: isDark ? Brightness.dark : Brightness.light)`. This re-installs `SystemUiOverlayStyle` so status-bar icons stay legible. Without this, on resume the icons sometimes flashed invisible in dark mode before `MaterialApp.builder` corrected it.

   - **Presence back online.** `PresenceService.setOnline(uid)` ([`presence_service.dart` lines 33–47](../../lib/src/services/presence_service.dart)):
     ```
     presence/{uid}.update({online: true, lastSeen: ServerValue.timestamp})
     presence/{uid}.onDisconnect().update({online: false, lastSeen: ServerValue.timestamp})
     ```
     The `onDisconnect` is re-registered (idempotent — RTDB replaces it).

7. **Video story rehydrate.** [`story_viewer_screen.dart` line 2530+](../../lib/src/features/screens/story_viewer_screen.dart):
   ```dart
   else if (state == AppLifecycleState.resumed && _suspended) {
     _suspended = false;
     _rebuildController(); // creates new VideoPlayerController, initializes, seeks to last known position
   }
   ```

8. **Firestore listeners auto-resume.** The SDK reconnects, snapshot listeners fire with the latest data.

9. **Locale + theme are preserved** — they live in `SharedPreferences` + Riverpod state and don't change across lifecycle transitions. See [13-language-and-theme-toggle-flow.md](13-language-and-theme-toggle-flow.md).

## Sign-out side path

[`main.dart` lines 254–273](../../lib/main.dart) listens on `authStateProvider`. When the user transitions from authenticated → null (sign-out), it:
- `FcmService().removeToken(previousUser.uid)` — removes the device's FCM token from `users/{uid}.fcmTokens`.
- `_presence.setOffline(previousUser.uid)` — RTDB write.
- `MessageCache.instance.clearAll()` — wipes the on-disk chat cache so the next user on this device can't see plaintext previews from the signed-out account.

On the opposite transition (null → authenticated):
- `FcmService().init(nextUser.uid)` — token registration.
- `_presence.setOnline(nextUser.uid)` — RTDB.

## Realtime Database writes

| Path | Trigger | Operation |
|------|---------|-----------|
| `presence/{uid}` | resume / sign-in | `update({online: true, lastSeen})`; `onDisconnect().update({online: false, lastSeen})` |
| `presence/{uid}` | pause / sign-out | `update({online: false, lastSeen})` |
| `typing/{chatId}/{uid}` | typing input | `set(true)`; `onDisconnect().remove()` (auto-cleared on socket drop, not lifecycle) |

## Firestore writes

| Path | Trigger | Operation |
|------|---------|-----------|
| `users/{uid}.fcmTokens` | sign-in | `arrayUnion([token])` |
| `users/{uid}.fcmTokens` | sign-out | `arrayRemove([token])` |

## Cloud Functions

None directly triggered by lifecycle. (Future enhancement: a presence-mirror function could write a `lastOnline` field to Firestore so that presence is readable by clients that don't have RTDB access — currently presence is RTDB-only.)

## Failure paths

- **RTDB not configured.** `PresenceService.setOnline` / `setOffline` wrap in try/catch — silent failure. Presence flag stays whatever it last was.
- **Pause fires multiple times in rapid succession.** Each fires another `setOffline` write — idempotent at the field level.
- **Resume but auth is gone** (token expired, user deleted while backgrounded). `ref.read(authStateProvider).value?.uid` is null → no presence write fires. The auth gate in the router redirects to `/login` shortly after.
- **Video controller dispose during a pending `initialize`.** Race-handled by `_rebuildController` re-checking `_suspended`/disposed state before assigning. Worst case: the resume rebuild bails and the story falls back to its thumbnail.
- **Status bar overlay race.** The brief flash mentioned in the code comment can still happen if the user resumes the app from a deep dark screen while `themeMode == dark`. The fix mitigates but doesn't eliminate.
- **`onDisconnect` not honored** (very rare). The user's `online: true` flag may stick until the next pause / resume cycle. RTDB-level concern; the app code is already defensive.

## Related files

- [`lib/main.dart`](../../lib/main.dart) — `_MyAppState.didChangeAppLifecycleState`, FCM/presence wiring, `_configureSystemUi`.
- [`lib/src/services/presence_service.dart`](../../lib/src/services/presence_service.dart)
- [`lib/src/services/typing_service.dart`](../../lib/src/services/typing_service.dart) — `onDisconnect` cleanup of typing flag.
- [`lib/src/services/fcm_service.dart`](../../lib/src/services/fcm_service.dart) — `init`/`removeToken` on auth change.
- [`lib/src/services/message_cache.dart`](../../lib/src/services/message_cache.dart) — `clearAll()` on sign-out.
- [`lib/src/features/screens/story_viewer_screen.dart`](../../lib/src/features/screens/story_viewer_screen.dart) — video controller teardown / rehydrate around `AppLifecycleState`.
- [`database.rules.json`](../../database.rules.json) — RTDB read/write rules for `presence/` and `typing/`.
