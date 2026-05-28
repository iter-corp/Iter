# Home Feed

## What this feature does
The home tab is a single screen (`HomeBody`) that switches between three modes via a `_HomeMode` enum: `feed` (default — followed-author posts + global feed), `travel` (location/place filtered posts), and `qa` (Discuss / Q&A questions). The chosen mode is persisted to `SharedPreferences` under `_kHomeModePrefsKey`. Above the mode tabs sits an admin-driven announcement banner and an orange maintenance banner; below them the story strip (`StoriesList`); below that a global search row + a primary "Post" action. Search is unified — typing collapses the header + story strip and merges hits from all three tabs into one ranked, de-duped list. The home tab is the destination of the bottom-nav `Home` slot (see `lib/src/features/widgets/botton_nav.dart`).

## Key screens / widgets
- [home_screen.dart](../../lib/src/features/screens/home_screen.dart) — single 3 300+ line file containing `HomeScreen`, `HomeBody`, all in-file widgets (`_HomeModeToggle`, `_NotificationBell`, `_ModeDropdown`, `_TravelLocationOffBanner`, `_QaThreadCard`, `_MiniPostPreview`, `_SearchPostRow`, `_AskQuestionSheet`, `_DiscussKindButton`, `_PlaceSearchScreen`, `_AnnouncementBanner`, `_MaintenanceBanner`, `_TravelQuickFilters`, `_TravelFilterChip`).
- [story_section.dart](../../lib/src/features/widgets/story_section.dart) — `StoriesList`, only mounted when `cfg.storiesEnabled` is true.
- [post_card.dart](../../lib/src/features/widgets/post_card.dart) — used for feed + travel hits; receives `travelMode`, `travelPlace`, `travelDistance` extras.

## Modes / tabs
- **Feed** — followed-authors-first feed via `feedProvider`. Renders `PostCard`s.
- **Travel** — `travelFeedProvider(TravelFeedQuery)` keyed by chosen place / current location. The screen surfaces `_TravelQuickFilters` (All / Nearby / recent places), a place search (`_PlaceSearchScreen`), and `_TravelLocationOffBanner` if the viewer hasn't granted location.
- **Discuss / Q&A** — `qaFeedProvider`. Renders `_QaThreadCard` (the in-file Q&A summary card) that taps through to `QaThreadScreen`. The "Post" button in this mode opens `_AskQuestionSheet` instead of `CreatePostScreen`.

## Search behavior
- A single `TextEditingController` + `FocusNode`. `_searchActive` = focused or has results; while active the announcement, maintenance, and stories rows collapse so the result list gets full screen.
- Question-text matching is synchronous; **answer-text matching** for Discuss runs as a 350 ms-debounced backend lookup (`PostService.qaPostsWithMatchingAnswer`) that yields a `Set<String>` of matching QA post ids and is cached against the current query.
- Results are merged across all three tabs and de-duped by `post.id` in the order Feed > Travel > Discuss. QA hits render as `_QaThreadCard`, others as `PostCard` (with `travelMode: true` for travel hits).
- An empty-state message uses `context.t.homeNoMatchingPosts`.

## Travel filter
- `_TravelFilterSheet` modal with options `__all_places__`, `__current_location__`, or specific places resolved via `PostService.searchTravelPlaces`.
- `_PlaceSuggestion` keeps `name`, `city`, `lat`, `lng`, `useCurrentLocation`. The chosen place re-keys `travelFeedProvider`.
- On resume from background, if the user had no location set and now does, the travel feed is invalidated automatically (`didChangeAppLifecycleState`).
- `_buildTravelQuery()` collapses the city to the part before any comma (so "Cairo, Egypt" becomes `Cairo`).

## Discuss / Q&A integration
- "Post" in Q&A mode opens `_AskQuestionSheet` which collects question text, optional details, and a `_discussKind` (`'question'` selected via `_DiscussKindButton`).
- Submit calls `PostService.createQaPost`. A `DiscussPostBlockedException` (server-side profanity / blacklist) triggers a dialog using `homeQuestionBlockedTitle` / `homeQuestionBlockedBody`.
- Pull-to-refresh on the QA tab invalidates `qaFeedProvider`.

## Maintenance + announcement banners
- `_MaintenanceBanner` — orange-tinted, shown when `cfg.maintenanceMode == true`. Text: `context.t.homeMaintenanceMode`.
- `_AnnouncementBanner` — pink/purple tinted, shown when `cfg.announcement` is non-empty.
- Both come from `adminConfigProvider` (Firestore `admin/config` doc — see `AdminService`).

## Location resolution
- Initial frame schedules `_ensureViewerLocation()`. Order of precedence: GPS → reverse geocoded city → `currentUserDocProvider`'s saved `location` + `city`.
- `_viewerCityLabel` returns a localized "Location unavailable" fallback when no city resolved.

## Firestore collections touched (indirectly via providers/services)
- `posts` (via `feedProvider`, `travelFeedProvider`, `qaFeedProvider`)
- `users` (via `currentUserDocProvider` for viewer location/city)
- `admin/config` (via `adminConfigProvider` for maintenance + announcement + `storiesEnabled`)
- `notifications/{uid}/items` (via the bell icon and `unreadActivityCountProvider`)

## Services used
- [post_service.dart](../../lib/src/services/post_service.dart) (`searchTravelPlaces`, `createQaPost`, `qaPostsWithMatchingAnswer`)
- [admin_service.dart](../../lib/src/services/admin_service.dart) (via `adminConfigProvider`)
- `geolocator`, `geocoding` for live GPS
- [post_providers.dart](../../lib/src/providers/post_providers.dart) (`feedProvider`, `travelFeedProvider`, `qaFeedProvider`)
- [comment_providers.dart](../../lib/src/providers/comment_providers.dart) (used by `_QaThreadCard` to show reply counts)
- [notification_providers.dart](../../lib/src/providers/notification_providers.dart) (drives the bell-icon badge)
- [auth_providers.dart](../../lib/src/providers/auth_providers.dart) (`currentUserDocProvider`)

## Non-obvious business rules
- The home Scaffold is `Colors.transparent` so the per-tab gradient painted by `MainScreen` shows through.
- Search active state pins the search row at the top via the in-file `_SearchPostRow`.
- Travel cards display a precomputed `post.travelDistanceLabel` if present.
- The bottom-nav `Home` tab maps directly to `HomeBody` and `_HomeMode` is restored from SharedPreferences on init.
- `_AskQuestionSheet` margin-tops by 25 % of screen height so the keyboard doesn't shove a full-height sheet off the top.
- Mode persistence failures are silently swallowed — the default mode is always `feed` if reading prefs throws.
- Discuss search runs two layers: instant question-text filter + 350 ms debounced answer-text Firestore lookup.

## Localization
~76 `context.t.*` calls in `home_screen.dart`.

## Related files
- `lib/src/features/screens/home_screen.dart`
- `lib/src/features/widgets/story_section.dart`
- `lib/src/features/widgets/post_card.dart`
- `lib/src/features/screens/create_post_screen.dart` (opened by the global "Post" button)
- `lib/src/features/screens/qa_thread_screen.dart` (opened from `_QaThreadCard`)
- `lib/src/features/screens/post_detail_screen.dart`
- `lib/src/features/screens/notification_screen.dart` (bell icon)
- `lib/src/providers/post_providers.dart`
- `lib/src/providers/admin_providers.dart`
- `lib/src/providers/notification_providers.dart`
- `lib/src/services/post_service.dart`
- `lib/src/services/admin_service.dart`
