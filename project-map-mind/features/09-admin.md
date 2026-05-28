# Admin

## What this feature does
A dashboard-style admin area (`AdminDashboardScreen`) gates each tile on `isAdminProvider == true` (the user's `role == 'admin'`). The dashboard surfaces 8 sub-screens: Users, Posts, Discuss posts, Reports (umbrella for post/user/discuss/error reports), Contact requests, Events, Blacklisted emails, and App settings. Org-admin (`role == 'org_admin'`) is a softer role that grants partial access (mainly events) — gated via `isOrgAdminProvider`. The flow gives admins moderation rights (delete post, resolve report, suspend user), content authoring (create/edit events), and global configuration (announcement banner, maintenance mode, feature toggles, profile field options, profanity word list, blacklisted emails).

## Role-based access
- `isAdminProvider` — `Provider<bool>` returning `(user?['role'] as String?) == 'admin'`.
- `isOrgAdminProvider` — same shape for `'org_admin'`.
- Stream providers (e.g. `adminPostsProvider`, `blacklistProvider`) early-return `Stream.empty()` when the viewer isn't an admin.
- `org_admin` users get a narrower surface: per code, an `org_admin` who is not a full `admin` will get an alternate event-list provider (see `admin_providers.dart`).
- The dashboard renders an "adminNoAccess" stub for non-admins.

## Key screens
- [admin_dashboard_screen.dart](../../lib/src/features/screens/admin/admin_dashboard_screen.dart) — 8 `_AdminTile` rows. Shows a red notification dot on Reports / Contact requests when `hasAnyNewReportsProvider` / `hasUnreadContactRequestsProvider` is true.
- [admin_users_screen.dart](../../lib/src/features/screens/admin/admin_users_screen.dart) — tabbed user list (All / Admins / Org admins / Suspended). Counts per bucket. Each `_UserTile` shows role + suspended badges and offers role / suspend actions (via `AdminService`).
- [admin_posts_screen.dart](../../lib/src/features/screens/admin/admin_posts_screen.dart) — paginated posts list with delete action (`adminServiceProvider.deletePost`).
- [admin_discuss_posts_screen.dart](../../lib/src/features/screens/admin/admin_discuss_posts_screen.dart) — same but for Q&A topics.
- [admin_reports_screen.dart](../../lib/src/features/screens/admin/admin_reports_screen.dart) — umbrella with 4 tiles: Post reports, User reports, Discuss reports, Error reports.
- [admin_post_reports_screen.dart](../../lib/src/features/screens/admin/admin_post_reports_screen.dart) — list of `postReports` docs. Resolve/unresolve via `setPostReportResolved(id, bool)` which writes `resolved` + `resolvedAt`.
- [admin_user_reports_screen.dart](../../lib/src/features/screens/admin/admin_user_reports_screen.dart) — `userReports`. `setUserProfileReportResolved`.
- [admin_discuss_reports_screen.dart](../../lib/src/features/screens/admin/admin_discuss_reports_screen.dart) — `discussReports`. `setDiscussReportResolved`.
- [admin_error_reports_screen.dart](../../lib/src/features/screens/admin/admin_error_reports_screen.dart) — `errorReports` captured by `ErrorReportService` (uncaught exceptions, FlutterError handler). Has filter / search / export actions.
- [admin_reports_toolbar.dart](../../lib/src/features/screens/admin/admin_reports_toolbar.dart) — shared toolbar (filter Resolved/Unresolved/All, search).
- [admin_contact_requests_screen.dart](../../lib/src/features/screens/admin/admin_contact_requests_screen.dart) — inbox for `contactRequests` (from "Contact Us" screen); mark read / reply / archive.
- [admin_events_screen.dart](../../lib/src/features/screens/admin/admin_events_screen.dart) — list + create/edit/delete admin events. `_EventFiltersSheet` for facet filters (`_FilterFacet`). Uses `image_picker` for event images, `CityPickerField` for location, `kEventTypes` / `kEventFundingStatuses` dropdowns. Delete dialog with confirmation.
- [admin_blacklist_screen.dart](../../lib/src/features/screens/admin/admin_blacklist_screen.dart) — blacklisted emails CRUD. Used to refuse signups for known-bad addresses.
- [admin_settings_screen.dart](../../lib/src/features/screens/admin/admin_settings_screen.dart) — global `AdminConfig` editor.

## Admin settings (`AdminConfig`)
Editable from `AdminSettingsScreen`:
- **Feature toggles** — `storiesEnabled`, `repostsEnabled`.
- **Maintenance** — `maintenanceMode` (renders the orange banner on home), `announcement` (free-text banner shown on home).
- **Profile options** — `profileProfessionOptions`, `profileFieldOptions`, `profileAcademicLevelOptions`, `profileGoalOptions`. Each is an add/remove chip list (minimum 1 entry — the last cannot be removed).
- **Event metadata** — `eventTypes`, `eventCountries` (overrides built-in constants).
- **Profanity** — `profanityWordsEn` (sorted on insert; rendered as removable chips). Used by `ProfanityFilterService` for posts / comments / chats.
- `_validateBadgeInput(value, existing)` — guards against duplicates and empty strings before insert.

## Report lifecycle (all 4 report types)
1. Created by `PostService.reportPost`, `PostService.reportQaPost`, `UserService.reportUserProfile`, or `ErrorReportService.captureXxx`.
2. Listed in the corresponding admin screen with toolbar facets (Unresolved by default).
3. Admin opens a row → side actions: View target (deep link), Resolve, Unresolve, Delete report.
4. `setXxxReportResolved(id, true)` stamps `resolved:true` + `resolvedAt: serverTimestamp()`.
5. `hasAnyNewReportsProvider` flips the dashboard red dot off when nothing is unresolved.

## Admin users moderation
- Buckets by role: `admin`, `org_admin`, `user`, and a separate **Suspended** bucket (a user with `suspended:true` is shown in Suspended regardless of role).
- Actions per user tile: promote / demote (set `role`), suspend / unsuspend (`suspended` bool), delete.

## Admin events authoring (`AdminEventsScreen`)
- Form fields: title, subtitle, description, link, phone, email, multiple image uploads, deadline date, event type, country, funding status, location pin (`CityPickerField` + `geo: {lat, lng}`), tags.
- Image uploads use `image_picker` + `StorageService`. Existing event images can be removed.
- Filter sheet on the list view filters by event type, funding status, country.
- Delete uses `_DeleteEventDialog` confirmation; calls `adminServiceProvider.deleteEvent(id)`.

## Blacklisted emails
- `AdminBlacklistScreen` adds/removes lower-cased emails to `admin/blacklist` doc.
- `AuthService.signUp` consults this list (via cloud rules) so blacklisted emails can't register.

## Error reports
- `ErrorReportService.captureFlutterError`, `captureZoneError`, `captureFunctionError` — invoked from `main.dart` + global error zones.
- Written to `errorReports/{id}` with stack trace + context. Admin screen lets the admin resolve / delete and filter.

## Firestore collections touched
- `users` (role / suspended writes).
- `posts` (delete).
- `postReports`, `userReports`, `discussReports`, `errorReports`.
- `events` (CRUD).
- `contactRequests`.
- `admin/config` (`AdminConfig`), `admin/blacklist`.
- Storage: `gs://.../events/`, `gs://.../users/`.

## Services used
- [admin_service.dart](../../lib/src/services/admin_service.dart) — all writes (`deletePost`, `deleteEvent`, `setPostReportResolved`, `setDiscussReportResolved`, `setUserProfileReportResolved`, `setUserSuspended`, `setUserRole`, `updateConfig`, etc.).
- [error_report_service.dart](../../lib/src/services/error_report_service.dart) — error capture.
- [contact_request_service.dart](../../lib/src/services/contact_request_service.dart) — contact CRUD.
- [storage_service.dart](../../lib/src/services/storage_service.dart) — admin event image uploads.

## Non-obvious business rules
- Each option-list in settings (`profession`, `field`, `academicLevel`, `goal`) has a **minimum of 1 entry** — the last one cannot be removed.
- The admin events delete flow uses a hard delete (`adminServiceProvider.deleteEvent`).
- Stream providers for admin lists early-return when the role check fails — this is also defense-in-depth against rules, not the only gate.
- The dashboard notification dot for Settings is currently wired to `hasUnreadContactRequests` (likely a copy-paste — verify in code: `showNotificationDot: hasUnreadContact` on the Settings tile).
- `AdminReportsScreen` is purely a router; the actual filtering UI is `admin_reports_toolbar.dart` shared between the four typed report screens.
- Admin error report list includes the source platform (iOS / Android), exception type, and pretty-stack summary.
- `BlackList`-based signup gating happens server-side; client merely surfaces the list.

## Localization
- Dashboard: 19. Settings: 40. Events: 67. User reports: 41. Post reports: 49. Discuss reports: 48. Error reports: 34. Contact requests: 21. Users: 27. Posts: 13. Discuss posts: 8. Reports: 9. Blacklist: 9. Toolbar: 0 (inherits parent text). Total across admin: ~400.

## Related files
- `lib/src/features/screens/admin/admin_dashboard_screen.dart`
- `lib/src/features/screens/admin/admin_users_screen.dart`
- `lib/src/features/screens/admin/admin_posts_screen.dart`
- `lib/src/features/screens/admin/admin_discuss_posts_screen.dart`
- `lib/src/features/screens/admin/admin_reports_screen.dart`
- `lib/src/features/screens/admin/admin_post_reports_screen.dart`
- `lib/src/features/screens/admin/admin_user_reports_screen.dart`
- `lib/src/features/screens/admin/admin_discuss_reports_screen.dart`
- `lib/src/features/screens/admin/admin_error_reports_screen.dart`
- `lib/src/features/screens/admin/admin_reports_toolbar.dart`
- `lib/src/features/screens/admin/admin_contact_requests_screen.dart`
- `lib/src/features/screens/admin/admin_events_screen.dart`
- `lib/src/features/screens/admin/admin_blacklist_screen.dart`
- `lib/src/features/screens/admin/admin_settings_screen.dart`
- `lib/src/services/admin_service.dart`
- `lib/src/services/error_report_service.dart`
- `lib/src/services/contact_request_service.dart`
- `lib/src/providers/admin_providers.dart`
- `lib/src/providers/admin_report_notifications_provider.dart`
- `lib/src/providers/contact_request_providers.dart`
