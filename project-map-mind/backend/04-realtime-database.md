# Realtime Database

Firestore is the system of record. Realtime Database (RTDB) is used **only** for two ephemeral, high-frequency signals where RTDB's `onDisconnect` cleanup is the right primitive:

1. Presence (online / last-seen)
2. Typing indicators

Rules: [`database.rules.json`](../../database.rules.json) — full content covered in [`03-security-rules.md`](03-security-rules.md).

## Path layout

```
presence/
  {uid}              { online: bool, lastSeen: server-timestamp }

typing/
  {chatId}/
    {uid}            true                                  // primitive boolean
```

That's the entire RTDB tree.

## Presence — [`presence_service.dart`](../../lib/src/services/presence_service.dart)

`PresenceService` owns `presence/{uid}`.

| API | Path touched | Effect |
| --- | --- | --- |
| `setOnline(uid)` | `presence/{uid}` | `update({online: true, lastSeen: ServerValue.timestamp})` then registers `onDisconnect().update({online: false, lastSeen})` so Firebase flips the user offline if the socket drops |
| `setOffline(uid)` | same | explicit `update({online: false, lastSeen})`, called on sign-out and on `AppLifecycleState.paused/inactive/detached/hidden` ([`main.dart:188-197`](../../lib/main.dart)) |
| `listenPresence(uid)` | same | maps `onValue` into `PresenceData(online, lastSeen)` |

The status text the UI shows is derived in `PresenceData.statusText` ([`presence_service.dart:13-22`](../../lib/src/services/presence_service.dart)) — "Online", "last seen just now", "last seen Xm/h/d ago".

Re-registration on resume: [`main.dart:177-187`](../../lib/main.dart) calls `setOnline(uid)` again whenever the app re-foregrounds, both to flip the flag and to re-arm the `onDisconnect` handler (RTDB clears it once it fires).

## Typing — [`typing_service.dart`](../../lib/src/services/typing_service.dart)

`TypingService` owns `typing/{chatId}/{uid}`.

| API | Effect |
| --- | --- |
| `setTyping(chatId, uid, true)` | `ref.set(true)` then `ref.onDisconnect().remove()` so a dropped socket clears the indicator |
| `setTyping(chatId, uid, false)` | `ref.remove()` |
| `listenTyping(chatId, otherUid)` | streams the boolean for the other user |

Used by chat input widgets — bubble shows the typing dots while another participant's flag is true.

## Subscription surfaces

Both services swallow errors with empty `try/catch` so the chat UI keeps working when RTDB is not configured (e.g. emulator without RTDB instance, web build that hasn't set up the SDK). The `PresenceData(online: false)` fallback in `listenPresence` is what you see in that degraded mode.

## When the app touches RTDB

- App startup / sign-in: `auth_state` listener in [`main.dart`](../../lib/main.dart) calls `_presence.setOnline(nextUser.uid)` once a user is signed in.
- Sign-out: `_presence.setOffline(previousUser.uid)`.
- Lifecycle transitions: `didChangeAppLifecycleState` toggles online/offline immediately (faster than waiting for `onDisconnect`).
- Chat screens: bubble widgets call `listenPresence` and `listenTyping`; the input field calls `setTyping` on debounced text changes (see chat input widgets under `lib/src/features/`).

## Related files

- [`database.rules.json`](../../database.rules.json)
- [`lib/src/services/presence_service.dart`](../../lib/src/services/presence_service.dart)
- [`lib/src/services/typing_service.dart`](../../lib/src/services/typing_service.dart)
- [`lib/main.dart`](../../lib/main.dart) — lifecycle wiring (lines 177-197, 254-272)
