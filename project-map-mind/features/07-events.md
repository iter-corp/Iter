# Events

## What this feature does
The Events tab (`EventBody` in `event_screen.dart`) lists `AdminEvent` documents — admin-curated opportunities (scholarships, internships, conferences, etc.) — with personalization, search, and a filter rail. Tapping a card opens `EventDetail` (full-screen detail with images, description, deadline, funding, contact, map, and registration button). Users register via `EventRegistrationSheet`, which writes to the registrations subcollection and registers them into the **auto-created `eventChats/{eventId}` group** (one chat per event, all registrants are members — see `06-chat-and-messaging.md` for `EventChatScreen`). A per-user `EventNotifPrefs` controls which event types and countries trigger push notifications. Events without an admin-set "available" status are caught by `EventUnavailableScreen`.

## Key screens / widgets
- [event_screen.dart](../../lib/src/features/screens/event_screen.dart) — 3000-line list/feed. Contains `EventBody`, `_MainToggle`, `_ToggleItem`, `_SearchBar`, `_PartnersView`, filter sheets, and a personalization sort that ranks events by goal/field/level matches against the viewer's profile.
- [event_detail.dart](../../lib/src/features/widgets/event_detail.dart) — full-screen detail view: image carousel, title, subtitle, description, deadline countdown, funding badge, location chip + map, contact pills, "Register" CTA.
- [event_registration_sheet.dart](../../lib/src/features/widgets/event_registration_sheet.dart) — modal registration form. Collects user details (`_EventRegistrationForm`), commits via `eventRegistrationProviders` → `EventRegistrationService`.
- [event_unavailable_screen.dart](../../lib/src/features/widgets/event_unavailable_screen.dart) — generic "this event is no longer available" screen with a Go Back button.
- [event_notifications_settings_screen.dart](../../lib/src/features/screens/event_notifications_settings_screen.dart) — per-user `EventNotifPrefs` editor: mode toggle (`all` / `selected` / `off`), event-type multi-select, country multi-select with inline search, save action.
- [location_map.dart](../../lib/src/features/widgets/location_map.dart) — `flutter_map` (OSM) widget with a single marker; used by event detail and post composer.

## Event types (`kEventTypes` from `admin_service.dart`)
**Note: the catalog is `Scholarship`, `Internship`, `Research`, `Conference`, `Summer Program`, `Competition`, `Leadership`, `Youth Summit`, `other`.** The brief described a different list; the actual constants in code are these. Admins may add/remove via `AdminSettingsScreen` so the live `AdminConfig.eventTypes` (kept in Firestore) supersedes the constant default.

## Funding statuses (`kEventFundingStatuses`)
`Fully Funded`, `Partially Funded`, `Self Funded`. Stored on the event doc as `funds` (empty on legacy docs).

## Countries (`kEventCountries`)
~200 entries (full ISO list + `Online`). Stored on the doc as `country` (display casing) and `locationCountry` (lower-cased key for matching).

## `AdminEvent` doc shape (`admin_service.dart`)
- `id`, `title`, `subtitle`, `description`, `link`, `phone`, `email`.
- `imageUrls: List<String>` — carousel images.
- `createdAt` (`Timestamp`), `deadlineAt` (`Timestamp` mapped from `deadline` field).
- `eventType` (one of `kEventTypes`), `country` (one of `kEventCountries`), `funds` (one of `kEventFundingStatuses`).
- `geo: { lat, lng }` → `lat`, `lng` doubles. Used by `LocationMap`.
- `createdByUid` (admin who created it).

## List filters (`EventBody` state)
- City filter (resolved via `CityPickerField`).
- Field filter (uses the cohort's `field` values).
- Academic level filter (uses the cohort's `academicLevel` values).
- Event type filter (single-select against `kEventTypes`).
- Country filter (single-select from a per-country search sheet).
- Free-text search (`_SearchBar` matches `title + subtitle + description + eventType`).
- Personalization: events whose `eventType` matches one of the viewer's goals (e.g. "Conferences" → `Conference`) are ranked higher.

## Registration flow
1. User taps "Register" on `EventDetail`.
2. `EventRegistrationSheet` opens with `_EventRegistrationForm`. Fields are collected client-side and validated.
3. `EventRegistrationService.register` (provider in `event_registration_providers.dart`) writes the registration doc.
4. Side effect: `eventChats/{eventId}/participants` adds the user → they appear in `EventChatScreen`.
5. The registration sheet may close immediately or surface a success state.

## Map view
`LocationMap` is shared between event detail and post composer. It uses `flutter_map` + `latlong2`. A single tappable marker opens external map apps via `maps_links.dart` (`Open in Maps` / `Get directions`).

## Per-user `EventNotifPrefs` (event notifications)
- `EventNotifMode`: `all`, `selected`, `off`.
- `types: List<String>` — list of `kEventTypes` keys (empty = all).
- `countries: List<String>` — lower-cased keys (empty = all).
- Persisted via `UserService.setEventNotifPrefs(uid, prefs)`.
- The screen normalizes "all types selected one by one" back into the empty/all state so the prefs read the same as if the user never customized.
- Country list is searched inline (200 countries is too many to scroll).
- Selected items pinned at top of the filtered list regardless of query.

## "Event unavailable" UX
`EventUnavailableScreen` is shown when the user navigates to an event that no longer exists or has been removed. Three keys: `eventUnavailableTitle`, `eventUnavailableBody`, `eventUnavailableGoBack`.

## Firestore collections touched
- `events/{eventId}` — `AdminEvent` doc.
- `events/{eventId}/registrations/{uid}` — registration doc.
- `eventChats/{eventId}` + `eventChats/{eventId}/messages` — auto-created chat per event.
- `users/{uid}` — `eventNotifPrefs` map, `profession`, `field`, `academicLevel`, `goals` for personalization sorting.
- `admin/config` — `eventTypes`, `eventCountries` overrides, default chip configuration.

## Services used
- [admin_service.dart](../../lib/src/services/admin_service.dart) — `kEventTypes`, `kEventCountries`, `kEventFundingStatuses`, `AdminEvent`, `AdminConfig`.
- [event_registration_service.dart](../../lib/src/services/event_registration_service.dart) — register/unregister + queries.
- [city_service.dart](../../lib/src/services/city_service.dart) — city picker.
- [user_service.dart](../../lib/src/services/user_service.dart) — `setEventNotifPrefs`.
- [notification_service.dart](../../lib/src/services/notification_service.dart) — fans out event notifications.
- `flutter_map`, `latlong2`, `geocoding` — map + reverse geocode.

## Non-obvious business rules
- Event chats are **auto-created per event**, one per `eventId`, with the event id as the chat id. All registrants become participants.
- City filter "deselect if already active": tapping the active chip clears the filter instead of opening the picker again.
- Country list is comprehensive (admins don't maintain it from settings). Event types ARE admin-maintained (`AdminConfig.eventTypes` from Firestore overrides the `kEventTypes` default at `cfg.eventTypes`).
- Personalization sort favors users whose `goals` include the event's `eventType` (goal ↔ event-type affinity).
- Registration form values can be different from the user's saved profile (registration is a one-time snapshot).
- `EventNotifPrefs` types/countries collapse to empty when every option is individually selected — this both saves storage and renders correctly as "All".
- Map fallback: events without `geo` have a null `lat/lng` and the map section is hidden.

## Localization
- `event_screen.dart`: ~70 `context.t.*` calls.
- `event_detail.dart`: ~10.
- `event_registration_sheet.dart`: ~15.
- `event_notifications_settings_screen.dart`: ~17.

## Related files
- `lib/src/features/screens/event_screen.dart`
- `lib/src/features/screens/event_notifications_settings_screen.dart`
- `lib/src/features/widgets/event_detail.dart`
- `lib/src/features/widgets/event_registration_sheet.dart`
- `lib/src/features/widgets/event_unavailable_screen.dart`
- `lib/src/features/widgets/location_map.dart`
- `lib/src/services/admin_service.dart`
- `lib/src/services/event_registration_service.dart`
- `lib/src/services/user_service.dart`
- `lib/src/providers/event_registration_providers.dart`
- `lib/src/providers/event_chat_providers.dart`
- `lib/src/providers/admin_providers.dart`
