# Utilities & Helpers

Small cross-cutting helpers live in [`lib/src/utils/`](../../lib/src/utils/). Each is self-contained and consumed broadly across screens.

## [`responsive.dart`](../../lib/src/utils/responsive.dart)

App-wide responsive primitives. Every widget should size against these helpers rather than hard-coding pixel values. The target is ≥360dp Android phones and ≥320pt iOS (iPhone SE 1st gen) without overflow.

**`Breakpoints` (px / dp):**
| Const | Value | Reference device |
|---|---|---|
| `xs` | 320 | iPhone SE 1st gen |
| `sm` | 360 | typical Android |
| `md` | 411 | Pixel-class |
| `lg` | 600 | small tablet / foldable inner |
| `xl` | 840 | tablet landscape |

**`extension ResponsiveContext on BuildContext`:**
| Member | Purpose |
|---|---|
| `screenWidth` / `screenHeight` | From `MediaQuery.sizeOf`. |
| `isXSmall` | `< Breakpoints.sm` (320–359dp). |
| `isCompact` | `< Breakpoints.md` (most Android in portrait). |
| `isTablet` | `>= Breakpoints.lg`. |
| `scaleW(double compact, double expanded)` | Linear interpolation between `compact` (at 320dp) and `expanded` (at 600dp), clamped. The workhorse for responsive padding/margins. |
| `responsive<T>({compact, medium?, expanded})` | Bucketed picker — returns `compact` below md, `medium` below lg, `expanded` above. |
| `safeTextScaler` | `MediaQuery.textScalerOf(this).clamp(min: 0.85, max: 1.25)` — respects accessibility but caps it. |
| `screenPadding` | `EdgeInsets.symmetric(horizontal: scaleW(12, 20))`. |
| `bottomSafeInset` | `MediaQuery.viewPaddingOf(this).bottom` (iOS home indicator / Android nav bar). |
| `topSafeInset` | `MediaQuery.viewPaddingOf(this).top` (status bar / notch / Dynamic Island). |

**`ResponsiveBootstrap`:** A `StatelessWidget` that wraps `child` in a clamped `MediaQuery` (text scaling 0.85x–1.25x). Used in `MaterialApp.builder` in [`main.dart`](../../lib/main.dart) so every screen inherits consistent text sizing.

**`FitText`:** Drop-in `Text` replacement for labels where wrapping isn't acceptable but accessibility scaling must be respected. Fades on overflow, shrinks font down to `minFontSize` (default 10) to fit. Internally uses `TextPainter` and binary-step search. Used for chip / tab / button / card-header labels.

## [`app_feedback.dart`](../../lib/src/utils/app_feedback.dart)

Snackbar helpers + a small toggle-icon animation.

**`AppFeedback` static class** — branded floating snackbar in three variants:

| Method | Background | Icon |
|---|---|---|
| `showSuccess(context, message)` | `AppColors.purple` | `check_circle_rounded` |
| `showInfo(context, message)` | `0xFF333333` | `info_outline_rounded` |
| `showError(context, message)` | `0xFFD7263D` | `error_outline_rounded` |

Also exposes `…On(ScaffoldMessengerState?, message)` variants so the caller can capture the messenger BEFORE popping a route (so the snackbar survives navigation). All snackbars are floating, rounded 14dp, 2s duration, with `clearSnackBars()` called first to prevent stacking.

**`PoppingActionIcon`** — animated icon that briefly bumps in scale (`1.0 → 1.35 → 1.0` over 280ms via `TweenSequence`) and switches between `inactiveIcon` and `activeIcon` when `active` toggles true. Used for save / bookmark / repost / like toggles so taps read as confirmed actions.

## [`maps_links.dart`](../../lib/src/utils/maps_links.dart)

Opens the device's maps app with directions from the user's current location to `(lat, lng)`. Uses the universal Google Maps directions URL — on iOS/Android this opens the installed maps app (Apple Maps falls back gracefully), otherwise the browser. **Free; no API key required.**

`Future<void> openDirectionsTo(BuildContext context, {required double lat, required double lng})`

Tries `launchUrl(LaunchMode.externalApplication)` for `maps/dir/?api=1&destination=…`; on failure falls back to `maps/search/?api=1&query=…`. Surfaces an `AppFeedback.showError` if both fail.

## [`media_cache.dart`](../../lib/src/utils/media_cache.dart)

App-wide disk cache for feed/travel/discuss content via the `flutter_cache_manager` package. Generous on purpose ("can cache large size"):

- **Capacity:** `_maxCacheObjects = 800`.
- **Stale period:** `Duration(days: 30)`.

**`MediaCache`** — static-only class with two separate cache managers so videos don't evict images:

| Member | Purpose |
|---|---|
| `static CacheManager images` | `'itrPostImageCache'`. Used by every `CachedNetworkImage` that renders feed/travel/discuss content. |
| `static CacheManager videos` | `'itrPostVideoCache'`. Used for post videos. |
| `static Future<File> videoFile(String url)` | Downloads + caches the post video on first call, then serves the on-disk copy on every later call. Same video never streams from the server twice. |
| `static Future<void> clear()` | Empties both image + video caches (powers a "Clear cache" setting). |

## [`share_app.dart`](../../lib/src/utils/share_app.dart)

Native share sheet for the "Invite friends" flow.

`Future<void> shareInviteLink(BuildContext context, AdminConfig config)` — picks the right store link for the running platform from `AdminConfig` (`iosAppStoreUrl` / `androidPlayStoreUrl`), falling back to the other store link if the platform-specific one is empty. On web, prefers Android's URL.

If neither URL is configured, surfaces `AppFeedback.showInfo` with "The app store link isn't set up yet — check back soon!".

Uses `share_plus` `Share.share(...)`. Sets `sharePositionOrigin` from the calling widget's `RenderBox` so iPad popover doesn't crash.

Message body:
```
Join me on Iter — connect with students, researchers and travellers, discover events and more:
<store-link>
```

## Related files

- [`lib/src/utils/responsive.dart`](../../lib/src/utils/responsive.dart)
- [`lib/src/utils/app_feedback.dart`](../../lib/src/utils/app_feedback.dart)
- [`lib/src/utils/maps_links.dart`](../../lib/src/utils/maps_links.dart)
- [`lib/src/utils/media_cache.dart`](../../lib/src/utils/media_cache.dart)
- [`lib/src/utils/share_app.dart`](../../lib/src/utils/share_app.dart)
- [`lib/main.dart`](../../lib/main.dart) — uses `ResponsiveBootstrap` in `MaterialApp.builder`.
- [`lib/src/theme/app_theme.dart`](../../lib/src/theme/app_theme.dart) — `AppColors` used by `AppFeedback`.
- [`lib/src/services/admin_service.dart`](../../lib/src/services/admin_service.dart) — `AdminConfig` consumed by `shareInviteLink`.
