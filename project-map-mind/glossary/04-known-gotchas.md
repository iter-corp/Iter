# Known gotchas

Non-obvious traps a future AI editor (or human) is likely to hit. Each entry has been verified against the code; cross-references point to the exact line that documents it.

---

## Lifecycle — `inactive` and `hidden` fire on transient focus loss

`AppLifecycleState.inactive` and `AppLifecycleState.hidden` fire whenever the app loses *focus* — pulling down the notification shade, opening the permission dialog, an incoming call, a screenshot overlay. They do **not** mean the user actually backgrounded the app.

Most lifecycle handlers should react only to `paused` and `detached`:

- **Story video player** (`lib/src/features/screens/story_viewer_screen.dart` line 2515): "We deliberately do NOT react to `inactive` or `hidden` — those fire on transient focus loss and tearing the codec down every time was overly aggressive and produced visible glitches." Only `paused` / `detached` tear down; `resumed` rebuilds.
- **Presence** in `lib/main.dart` line 188 currently *does* fire offline on `inactive` / `hidden` too, by design: peers should see you go offline immediately rather than wait for the socket to drop. That's the deliberate exception — when "going offline" is itself the visible state, eager wins.
- **Camera** (`lib/src/features/screens/camera_story_screen.dart` line 64) *does* tear down on `inactive` because Android can silently revoke the camera surface on overlay events.

Bottom line: copy the matching screen's lifecycle handler — don't pattern-match all four states by default.

---

## Android video codec releases the output surface on background

On Android, when the activity is backgrounded the OS releases the video codec's output surface. When the app returns, `VideoPlayerController` still reports `isInitialized == true` but renders a **black frame**. There is no "is the surface alive" API to check.

Fix is in `_VideoStoryView.didChangeAppLifecycleState` (`story_viewer_screen.dart` lines 2506–2533): on `paused`/`detached`, dispose the controller; on `resumed`, recreate it (`_setup(resumeFrom: _lastKnownPosition)`). The old position is remembered so playback resumes where the user left off. The widget short-circuits to a spinner while `_suspended == true` so the broken-image placeholder doesn't flash in during the codec restart.

If you add a new video player anywhere in the app, copy this pattern.

---

## `WidgetsBindingObserver.didChangeAppLifecycleState` and `context.t.*` after async gaps

`didChangeAppLifecycleState` is a *callback* — there's no `Element` mount check around it like `build()` provides. If you `await` something inside the handler, `context` may no longer be safe to use.

Worse: `context.t.*` (the `AppStrings` getter) calls `Localizations.localeOf(this)`, which assumes the widget is still in the tree. After an async gap on a lifecycle path, that's not guaranteed.

**Resolve all localized strings up-front, before the first `await`.** Don't reach into `context.t` deep inside an async lifecycle method.

The compile-time enforcement of this in the codebase comes from preferring `unawaited(...)` and synchronous reads in lifecycle handlers (see `lib/main.dart` lines 172–198, `story_viewer_screen.dart` lifecycle paths).

---

## Kurdish (`ckb`) is not bundled with Flutter

`flutter_localizations` ships built-in Material, Cupertino, and Widgets localizations for ~80 locales but **not** Kurdish Sorani. Without a delegate that claims `ckb`, framework widgets (date pickers, dialogs, `Directionality`, tooltip semantics) throw `"No <Foo>Localizations found"`.

The project ships a custom delegate (`lib/src/l10n/ckb_material_localizations.dart`) that maps every `ckb` request onto Arabic (`ar`) localizations:

- `CkbMaterialLocalizations.delegate`
- `CkbCupertinoLocalizations.delegate`
- `CkbWidgetsLocalizations.delegate` (this is what supplies the ambient RTL `TextDirection` to the whole subtree)

User-facing text still comes from `strings_ckb.dart`; only framework chrome ("Cancel" inside a stock date picker) falls back to Arabic. **All three Ckb delegates must come before `GlobalMaterialLocalizations.delegate` etc. in the `localizationsDelegates` list** (see `lib/main.dart` lines 309–319) so they win the resolution race.

If you add another non-bundled locale, mirror this three-delegate setup.

---

## Discuss reuses the Post collection

A Discuss (Q&A) thread is *not* a separate collection — it's a document in `posts/` tagged with `postType: 'qa'` and `discussKind: 'question'` or `'discussion'`. Verified in `lib/src/services/post_service.dart` lines 251–263 (`createQaPost`) and `lib/src/features/model/post_model.dart` lines 22–31.

Consequences:

- Any new query against `posts/` must filter by `postType` (or its absence) to avoid mixing QA threads into the regular feed. `streamFeed` and `streamQaFeed` show the canonical filters.
- Comments on a Discuss post are answers; the same `comments/` subcollection is used.
- A "promoted" Discuss thread (created from an existing feed post) sets `sourcePostId` on the QA doc *and* writes `discussTopicId` back to the source post so the original post's menu can switch to "View in Discuss". The promotion path bails out and returns the existing topic id if one already exists, preventing duplicates (`createQaPostFromPost`).

---

## Report reasons are stored as English keys

Reports (`postReports`, `discussReports`, `userProfileReports`) store `reason` as the English string the user picked from the dropdown, e.g. `'Spam or scam'` — not as a numeric enum or a localized string. This keeps the admin dashboard consistent regardless of locale.

The UI must translate via the helper:

```dart
Text(context.t.reportReasonLabel(report.reason))
```

`reportReasonLabel` is a `switch` over the canonical English strings (`lib/src/l10n/app_strings.dart` lines 1907–1930). Unknown values fall through to themselves so unmigrated docs render readably.

When adding a new report reason: add it to `_reportReasons` in `post_card.dart`, add a key in each `strings_*.dart`, add a getter on `AppStrings`, and add a `case` to `reportReasonLabel`. Touch all four or the round-trip breaks.

The same English-keys-on-doc pattern applies to roles (`'admin'` / `'org_admin'` / `'user'`) and notification `type` values.

---

## Firebase project: `coil-50528`

The live project is `coil-50528`, verified in `lib/firebase_options.dart` (lines 53, 62, 71 — `projectId: 'coil-50528'` for web/Android/iOS). The Realtime Database is in `asia-southeast1` (`https://coil-50528-default-rtdb.asia-southeast1.firebasedatabase.app`). The Android/iOS bundle id is `com.iter.ai`. Storage bucket is `coil-50528.firebasestorage.app`.

If you ever see `coil-9239e` references anywhere in the repo, those are stale leftover FlutterFire config from the prior project and should be removed. There are currently no live references in the source tree.

---

## `node_modules/` was previously tracked in git

`node_modules` is listed in `.gitignore` (line 68) but a directory was historically committed at the repo root before the ignore rule was added. It has since been cleaned (verified: no `node_modules` directory in the working tree; the only matching path is inside `functions/package-lock.json`).

If you regenerate or re-add `node_modules/` (e.g. running `npm install` in the repo root), Git will *not* re-add it because `.gitignore` now covers it — but if you ever see it appearing in `git status`, double-check the ignore rule is intact.

---

## `Firebase.initializeApp` must be called inside the guarded zone

`ErrorReportService.instance.runGuarded(() async { ... })` wraps the **entire** startup. `WidgetsFlutterBinding.ensureInitialized()`, `Firebase.initializeApp(...)`, and `runApp` must all be inside that callback. Flutter asserts that the binding is initialized in the same zone that later calls `runApp` — if you split them, the framework throws.

This is documented in `lib/main.dart` lines 36–40.

---

## `ErrorReportService` instance singleton must not touch Firestore eagerly

`ErrorReportService.instance` is referenced in `main()` *before* `Firebase.initializeApp(...)` (to set up the guarded zone). Therefore the singleton's constructor and field initializers must **not** call `FirebaseFirestore.instance` — that would crash with "FirebaseApp not initialized."

The fix is a lazy `_db` getter (`lib/src/services/error_report_service.dart` lines 23–28): returns `null` until `Firebase.apps` is non-empty, then memoizes the handle.

Mirror this pattern for any other singleton that may be touched pre-Firebase-init.

---

## Auth-state transient null

`FirebaseAuth.authStateChanges` briefly emits `null` between `signInWithCredential` completing and the user doc being written during signup. `MyApp.build` defends against accidentally signing users out by requiring a prior non-null `currentUserDocProvider` value before treating "doc missing" as a real deletion:

```dart
final wasPresent = prev?.value != null;
final nowMissing = next.hasValue && next.value == null;
if (authed && wasPresent && nowMissing) {
  unawaited(ref.read(authServiceProvider).signOut());
}
```

If you rewrite this listener, preserve the `wasPresent` gate — without it, fresh sign-ups race their own user-doc creation and get instantly signed out.

The same idea explains the `await user.getIdToken()` + 50ms delay in `authStateProvider` (`lib/src/providers/auth_providers.dart` lines 56–75): Firestore streams opened in the gap between `signInWithCredential` returning and the Firestore SDK seeing the new token produce transient `permission-denied`. The retry stream (`_retryStream`) is the second line of defense.

---

## iOS FCM token requires APNS token first

`FcmService.init` polls for the APNS token before requesting the FCM token on iOS/macOS (`lib/src/services/fcm_service.dart` lines 66–87). `getToken()` fails on iOS unless an APNS token is already set, and the OS sometimes doesn't have one yet on first launch.

If the poll times out (10 × 500ms = 5s), the service registers `onTokenRefresh` and bails out for the session — the token will eventually be persisted on the next refresh.

Don't call `getToken()` directly on iOS without this APNS check.

---

## Cloud emulator must be opt-in

`USE_FIREBASE_EMULATOR=true` in `.env` enables emulator wiring; default is off. On a real device, `localhost` resolves to the phone, not the dev machine, so leaving the emulator on caused every callable/Firestore call to hang. When testing on physical hardware, set `FIREBASE_EMULATOR_HOST` to the dev machine's LAN IP. See `lib/main.dart` lines 83–100.

---

## `node_modules`, `build/`, `.dart_tool/`, `ios/Pods/` etc. — don't `git add .`

Routine cleanliness: prefer adding specific files rather than `git add .` to avoid sweeping in build artifacts, generated FlutterFire configs, or `.env` files. The repo's `.gitignore` covers the common cases, but the cost of a slip-up here is large diffs and possible secret leakage.

---

## Story progress bar needs a polling timer

`VideoPlayerController.addListener` only fires on coarse state changes (play/pause/seek), not on every painted frame. Driving the story progress bar from `addListener` makes it tick jerkily — sometimes appearing not to move at all.

The fix in `story_viewer_screen.dart` (lines 2405–2410) is a `Timer.periodic(~60ms)` that polls `c.value.position` and feeds the bar a smooth 60ms cadence. The timer is started/stopped alongside the controller's lifecycle (`_stopPositionTimer()` is called on every teardown path).

If you add a video-with-progress widget elsewhere, copy the timer pattern.

---

## Story trim window is *not* baked into the file

`videoTrimStartMs` / `videoTrimEndMs` on a story doc are *playback hints* — the underlying video file in Storage is unchanged. The viewer clamps playback to the window (and seeks to the start before playing). Either bound may be null.

Defensive note from `story_viewer_screen.dart` line 2450: malformed trim windows (start ≥ end, both null, etc.) fall back to the full video. Apply the same defensive default if you ever consume these fields elsewhere.

---

## `node_modules` aside: Cloud Functions live in `functions/`

The Cloud Functions package has its own `package.json` and `node_modules/` (inside `functions/`). That is ignored, not tracked. The Dart side does not depend on Node for development.

---

## Don't import models from screens directly

Models live in `lib/src/features/model/` (`post_model.dart`, `message_model.dart`, `story_comment_model.dart`, and `main_screen.dart` which is the bottom-tab shell). However some "models" are co-located with their service (e.g. `AdminEvent`, `AdminConfig`, `PostReport`, `UserProfileReport`, `AppNotification`, `Story`, `StoryViewer`, `ChatMessage`, `EventChatMessage` all live next to their service in `lib/src/services/`). When you need a model, search by class name rather than guessing its location.

---

## Related files

- `lib/main.dart` — startup, lifecycle, FCM tap routing, version gate
- `lib/firebase_options.dart` — project ID `coil-50528`
- `lib/src/features/screens/story_viewer_screen.dart` — codec teardown, navToken, trim window
- `lib/src/features/screens/camera_story_screen.dart` — camera lifecycle (deliberately reacts to `inactive`)
- `lib/src/features/screens/video_story_preview_screen.dart` — minimal pause-on-inactive
- `lib/src/services/error_report_service.dart` — lazy Firestore handle, guarded zone
- `lib/src/services/fcm_service.dart` — APNS poll on iOS
- `lib/src/providers/auth_providers.dart` — token settle + retry stream
- `lib/src/l10n/ckb_material_localizations.dart` — Kurdish → Arabic mapping
- `lib/src/l10n/app_strings.dart` — `reportReasonLabel(englishKey)`
- `lib/src/services/post_service.dart` — Discuss reuses `posts/`
- `lib/src/features/model/post_model.dart` — `discussKind`, `discussTopicId`, `sourcePostId`
- `.gitignore` — historical `node_modules` cleanup
