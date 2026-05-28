# Error Reporting

The app has a homegrown, **lightweight** error logging system instead of Crashlytics / Sentry. Uncaught errors (Flutter framework, async / zone, platform) are written to a Firestore `errorReports` collection so admins can review them in the dashboard. The reporter is rate-limited so a tight error loop can't blow up the bill on the Spark plan.

Implementation lives in a single file: [`lib/src/services/error_report_service.dart`](../../lib/src/services/error_report_service.dart).

## Pieces

- `ErrorReportService` — singleton (`.instance`) that owns the rate limiter, screen tracker, and `report()` writer.
- `ErrorReportNavigatorObserver` — Navigator observer that keeps the current screen label fresh.
- `ErrorReport` model + `ErrorReportAdmin` reader for the admin dashboard.

## How errors get captured

There are three independent capture paths, all wired up in [`lib/main.dart`](../../lib/main.dart):

### 1. The guarded zone (async / zone errors)

The entire `main()` body runs inside `ErrorReportService.instance.runGuarded(...)`:

```dart
ErrorReportService.instance.runGuarded(() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureSystemUi();
  await dotenv.load(...);
  await Firebase.initializeApp(...);
  ErrorReportService.instance.install();
  ...
  runApp(ProviderScope(...));
});
```

`runGuarded` calls `runZonedGuarded` with `(error, stack) => report(error, stack, kind: 'zone')`. **Critically, `WidgetsFlutterBinding.ensureInitialized()` is called INSIDE the zone** because Flutter asserts that the binding init and `runApp` happen in the same zone. Errors thrown in timers, futures, or async callbacks after `main` returns are still caught — the zone outlives the function body.

### 2. `FlutterError.onError` (Flutter framework errors)

`ErrorReportService.install()` chains onto whatever existing handler exists:

```dart
final previousOnError = FlutterError.onError;
FlutterError.onError = (FlutterErrorDetails details) {
  previousOnError?.call(details);
  report(details.exception, details.stack,
         context: details.context?.toString(), kind: 'flutter');
};
```

There's also a small filter in `main.dart` BEFORE `install()` that swallows known noisy frames:

```dart
if (details.exceptionAsString()
    .contains('EncodingError: The source image cannot be decoded') ||
    details.library == 'image resource service') {
  return;
}
```

### 3. `PlatformDispatcher.instance.onError` (errors that escape to the platform)

Same `install()` call:

```dart
PlatformDispatcher.instance.onError = (error, stack) {
  report(error, stack, kind: 'platform');
  return true; // mark handled
};
```

This catches errors that escape the zone (e.g. errors thrown from synchronous OS callbacks).

`install()` must run AFTER `Firebase.initializeApp()` — the service falls back to a no-op write if Firestore isn't initialized.

## Manual reporting

Any catch block can hand-log via:

```dart
ErrorReportService.instance.report(
  error,
  stack,
  context: 'Optional extra string',
  kind: 'manual',         // or 'flutter' / 'zone' / 'platform' / your own
  screen: 'OptionalLabel', // overrides the observer's current screen
);
```

Used sparingly across the codebase — the global handlers usually cover it.

## Current-screen tracking

Every report includes which screen the user was on. Two complementary mechanisms:

### `ErrorReportNavigatorObserver`

Registered in the `GoRouter` config (`observers: [ErrorReportNavigatorObserver()]`). Sets `_currentScreen` on every `didPush` / `didPop` / `didReplace` / `didRemove`:

```dart
_currentScreen = route.settings.name?.trim() ?? '';
if (_currentScreen.isEmpty) {
  // Unnamed route (MaterialPageRoute(builder: ...)) — fall back to runtime type.
  _currentScreen = route.runtimeType.toString();
}
```

### `setCurrentScreen(String? screen)`

Called explicitly from screens that aren't tracked well by the observer. The most prominent caller is [`MainScreen`](../../lib/src/features/model/main_screen.dart): every tab switch calls

```dart
ErrorReportService.instance.setCurrentScreen('Home' | 'Events' | 'Translate' | 'Messages' | 'Profile');
```

so the tab name is attached to any error happening on that tab.

## Rate limiting

Three layers, all in `report()`:

1. **De-dup window:** the same `signature = '$kind|${message.split("\n").first}'` is suppressed if seen within the last 2 minutes (`_recentSignatures`).
2. **Session cap:** `_maxPerSession = 25` total writes per app session.
3. **Min gap:** `_minGap = 3 seconds` between consecutive writes.

If `Firebase.apps.isEmpty` (Firebase not initialized yet), the write is skipped silently. The whole `report()` body is wrapped in `try {...} catch (_) {}` so the reporter can never itself crash the app.

## Document shape — `errorReports/` collection

Each report is a doc in the top-level `errorReports` collection with these fields:

| Field | Type | Notes |
|---|---|---|
| `message` | string | `error.toString()`. |
| `stack` | string | Trimmed to ≤ 6000 chars. |
| `kind` | string | `'flutter'`, `'zone'`, `'platform'`, `'manual'`, or whatever the caller passed. |
| `context` | string? | From `FlutterErrorDetails.context` or the caller's `context:` arg. |
| `screen` | string? | The observer's current screen, OR the caller's `screen:` override. |
| `uid` | string? | `FirebaseAuth.instance.currentUser?.uid`. |
| `platform` | string | `defaultTargetPlatform.name`. |
| `appVersion` | string | From `PackageInfo.fromPlatform()` (fetched lazily on `install`). |
| `resolved` | bool | Always `false` on write. |
| `createdAt` | Timestamp | `FieldValue.serverTimestamp()`. |

Document IDs are auto-generated (`.add(...)`).

## Admin dashboard side

`ErrorReportAdmin` provides the dashboard's read/write API:

| Method | Purpose |
|---|---|
| `Stream<List<ErrorReport>> stream({int limit = 200})` | Newest first, capped at 200. |
| `Future<void> setResolved(String id, bool resolved)` | Toggle the flag. |
| `Future<void> delete(String id)` | Single-doc delete. |
| `Future<int> clearResolved()` | Batch-deletes the next 400 docs where `resolved == true`. |

These are exposed via Riverpod as:

- `errorReportAdminProvider` — `Provider<ErrorReportAdmin>` (singleton).
- `errorReportsProvider` — `StreamProvider<List<ErrorReport>>` (auth-gated + admin-gated).
- `hasNewErrorReportsProvider` — derived bool from [`admin_report_notifications_provider.dart`](../../lib/src/providers/admin_report_notifications_provider.dart). Compares the newest unresolved report's `createdAt` against the last "seen at" timestamp saved in SharedPreferences (`admin_error_reports_seen_at_ms`). The admin dashboard tile shows a dot if true.

The admin error-reports screen lets admins:
- Browse newest-first.
- Tap a report to see message + stack + screen + uid + platform + appVersion.
- Toggle `resolved`.
- Delete individual reports or clear all resolved at once.
- "Mark seen" via `AdminReportSeenNotifier.markErrorReportsSeen()` so the dot disappears.

## Related files

- [`lib/src/services/error_report_service.dart`](../../lib/src/services/error_report_service.dart) — `ErrorReportService`, `ErrorReportNavigatorObserver`, `ErrorReport`, `ErrorReportAdmin`.
- [`lib/main.dart`](../../lib/main.dart) — `runGuarded` wrapper, `FlutterError.onError` chain (with image-decode filter), `install()` call after `Firebase.initializeApp()`.
- [`lib/src/router/app_router.dart`](../../lib/src/router/app_router.dart) — `observers: [ErrorReportNavigatorObserver()]`.
- [`lib/src/features/model/main_screen.dart`](../../lib/src/features/model/main_screen.dart) — `_trackTab` → `setCurrentScreen`.
- [`lib/src/providers/admin_providers.dart`](../../lib/src/providers/admin_providers.dart) — `errorReportAdminProvider`, `errorReportsProvider`.
- [`lib/src/providers/admin_report_notifications_provider.dart`](../../lib/src/providers/admin_report_notifications_provider.dart) — `hasNewErrorReportsProvider`, seen-at tracking.
