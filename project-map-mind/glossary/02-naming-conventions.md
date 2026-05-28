# Naming conventions

Patterns extracted from `lib/`. When in doubt, mirror an existing nearby file — the codebase is internally consistent.

---

## Files

| Concern | Convention | Example |
| --- | --- | --- |
| Dart file names | `snake_case.dart` | `home_screen.dart`, `event_chat_service.dart`, `story_comment_model.dart` |
| One screen per file | Yes — each full-page UI is its own file under `lib/src/features/screens/` | `chat_screen.dart`, `profile_settings_screen.dart` |
| Sub-grouping | Auth screens in `screens/auth/`, admin screens in `screens/admin/` | `screens/auth/login_screen.dart`, `screens/admin/admin_dashboard_screen.dart` |
| Widgets vs models vs services | Separate top-level directories under `lib/src/features/` and `lib/src/` | `features/widgets/post_card.dart`, `features/model/post_model.dart`, `services/post_service.dart` |
| L10n strings | Map literals in `lib/src/l10n/strings_<locale>.dart` (`en`, `ar`, `ckb`) and getters in `app_strings.dart` | `strings_en.dart`, `app_strings.dart` |

There is no codegen for localization — `AppStrings` looks up `Map<String, String>` per `AppLanguage`.

---

## Classes

| Kind | Convention | Example |
| --- | --- | --- |
| Public class | `PascalCase` | `PostCard`, `ChatMessage` |
| Full-page screen | `XxxScreen` | `HomeScreen`, `ChatScreen`, `AdminDashboardScreen` |
| Reusable widget | `XxxWidget` only when ambiguous; usually a bare noun | `PostCard`, `NotificationTile`, `MessageWidget`, `AppGlassCard` |
| Tab body inside `MainScreen` | `XxxBody` (the in-tab page rendered by the bottom-nav `PageView`) | `HomeBody`, `EventBody`, `MessageBody`, `TranslateBody` |
| Domain model | Bare noun, no suffix | `Post`, `ChatMessage`, `Story`, `AppNotification`, `AdminEvent` |
| Service | `XxxService` | `PostService`, `ChatService`, `NotificationService`, `FcmService` |
| Provider state class | `XxxNotifier` (`StateNotifier`) | `LocaleNotifier` |
| `ConsumerStatefulWidget` `State` | `_XxxState extends ConsumerState<Xxx>` | `_HomeBodyState`, `_MainScreenState`, `_PostCardState` |
| File-local widgets | Prefixed `_` and live in the same file as the screen that consumes them | `_HomeModeToggle`, `_NotificationBell`, `_TravelFilterSheet`, `_VersionGate`, `_AdminTile` |

### Private vs public

Anything intended only for use inside the file (a small composite widget, an enum, a helper class, a private state class) is prefixed `_` and never imported. Examples in `home_screen.dart`: `_PlaceSuggestion`, `_HomeModeToggle`, `_NotificationBell`, `_ModeDropdown`, `_QaThreadCard`. The `State` class for every `StatefulWidget` is also private (`_HomeBodyState`).

---

## Providers (Riverpod)

| Kind | Naming | Example |
| --- | --- | --- |
| Service provider | `xxxServiceProvider` (the lowercase service name + `Provider`) | `postServiceProvider`, `adminServiceProvider`, `authServiceProvider` |
| Stream of data | `xxxProvider` (the noun + `Provider`) | `feedProvider`, `qaFeedProvider`, `authStateProvider`, `currentUserDocProvider`, `adminConfigProvider` |
| Predicate / role | `isXxxProvider` | `isAdminProvider`, `isOrgAdminProvider` |
| Family-keyed provider | Same `xxxProvider` name, parameter is a primitive or a `==`-overriding value class | `singlePostProvider`, `userPostsProvider`, `travelFeedProvider`, `userByUidProvider` |
| Has-flag | `hasXxxProvider` | `hasAnyNewReportsProvider`, `hasUnreadContactRequestsProvider` |

All providers live under `lib/src/providers/`, one file per domain (`auth_providers.dart`, `admin_providers.dart`, `post_providers.dart`, …).

---

## Firestore field names

camelCase, even though file names and l10n keys are snake_case.

| Field | Notes |
| --- | --- |
| `authorUid`, `authorUsername`, `authorAvatar` | Denormalized author info on posts/comments/stories |
| `createdAt`, `expiresAt`, `resolvedAt`, `deadlineAt`, `lastSeen`, `viewedAt` | `Timestamp` |
| `likesCount`, `commentsCount` | Int counters |
| `imageUrls`, `videoUrls` | `List<String>` |
| `isPrivate`, `read`, `resolved`, `online`, `profanityFiltered`, `storiesEnabled`, `repostsEnabled` | Booleans, prefer affirmative naming |
| `targetId`, `targetUid`, `actorUid`, `reporterUid`, `senderUid` | UID / id pointers |
| Geo data | Top-level `lat`/`lng` *inside* a nested map (`postLocation.lat`, `geo.lat`, `location.lat`) — not flat columns |
| Money/funding | `funds` (string label, e.g. `"Fully Funded"`) — see `kEventFundingStatuses` |
| Country | `country` (admin's original casing for display) + `locationCountry` (lower-cased, used for matching) |

---

## Localization keys vs i18n getters

The map keys and Dart getters share a meaning but differ in case style.

| Layer | Style | Example |
| --- | --- | --- |
| Firestore-stored backend value | English string verbatim (English is the canonical key) | `'Spam or scam'`, `'admin'`, `'Fully Funded'` |
| L10n map key in `strings_*.dart` | `snake_case_with_domain_prefix` | `home_no_matches`, `event_notif_title`, `admin_settings_section_profanity`, `report_reason_spam`, `qa_untitled_question` |
| Getter on `AppStrings` | `camelCase`, mirroring the key | `homeNoMatches`, `eventNotifTitle`, `adminSettingsSectionProfanity`, `reportReasonSpam`, `qaUntitledQuestion` |
| Parameterized getter | `camelCase` + `(args)` returning the formatted string | `helloName('Sara')`, `timeAgo(post.createdAt)`, `reportReasonLabel(englishKey)`, `updateRequiredBody(required, current)` |

Place-holders inside the translated string use `{name}` syntax and are substituted by `_fmt`. See `lib/src/l10n/app_strings.dart` lines 41–47.

---

## Comments

Three patterns appear consistently:

| Pattern | Used for | Example location |
| --- | --- | --- |
| `// ─── SECTION HEADER ───` (with box-drawing dashes) or `// 📌 SECTION: …` | Top-level boxed dividers between logical sections of a long file | `lib/main.dart` line 347, `lib/src/services/notification_service.dart` lines 3 & 62, `lib/src/features/model/main_screen.dart` lines 89, 102, 121 |
| `/// triple-slash doc comment` on a class or non-trivial method | Public API of services, models, and notable widgets — explains *why-not-what* and lists Firestore implications | `Post.discussTopicId`, `Story.videoTrimStartMs`, `PresenceService.setOnline`, `AppStrings.reportReasonLabel` |
| `// inline "why" comment` | Non-obvious decisions, race fixes, or platform quirks. Often multi-line and uses prose, not bullet lists | `lib/main.dart` lines 192–197 (presence on background), `lib/src/features/screens/story_viewer_screen.dart` lines 2506–2532 (Android codec teardown), `lib/src/providers/auth_providers.dart` lines 58–69 (auth-token propagation) |

The codebase **does not** comment trivia like "increment count by 1" — comments explain why a chunk of code exists or what bug it prevents.

---

## Colors and theme tokens

The project deliberately avoids raw `Colors.black` / `Colors.white` for content text. Use the extensions on `BuildContext` defined in `lib/src/theme/app_theme.dart`:

| Token | Meaning |
| --- | --- |
| `context.isDark` | `bool` — current Material brightness |
| `context.theme`, `context.colors` | `Theme.of(this)`, `Theme.of(this).colorScheme` |
| `context.textPrimary` | Foreground body text |
| `context.textSecondary` | Muted body / subtitle |
| `context.textMuted` | Hint / placeholder |
| `context.surfaceSoft` | App background tint |
| `context.cardBg` | Card surface |
| `context.inputFill` | Text field fill |
| `context.borderColor` | Hairline/border |
| `context.purpleSoft` | Tinted brand surface |
| `context.tagBg` | Yellow/orange tag chip |
| `AppColors.purple`, `purpleBright`, `purpleDeep`, `purpleVivid`, `green`, `red`, `orange` | Brand constants |

`Colors.black` / `Colors.white` *are* used, but only for high-contrast UI chrome that's the same in both themes (e.g. the dark glass pill behind the bottom nav, the white selection bubble on it).

---

## Localization access

Always via the `context.t` extension on `BuildContext` (defined at the bottom of `app_strings.dart`):

```dart
Text(context.t.settings)
Text(context.t.helloName('Sara'))
```

Never call `AppStrings(language)` directly in build code — `context.t` re-reads `Localizations.localeOf(this)` so widgets rebuild on locale change.

---

## Other observed conventions

- **Imports**: `package:` imports first, then a blank line, then relative `'../...'` imports. Inside the relative block, project files are roughly grouped by layer (services together, providers together, etc.).
- **Doc comments use Markdown**: `[ClassName]`, `[methodName]` link targets in dartdoc style.
- **Field ordering on models**: required positional/final fields first, optional ones last; `factory fromDoc(DocumentSnapshot ...)` directly follows the constructor.
- **`debugPrint` over `print`**: any developer logging uses `debugPrint('[Tag] message')` with a short bracket tag (`[PostService]`, `[boot]`). See `lib/main.dart` and `lib/src/services/post_service.dart`.
- **Singleton accessor**: `Xxx.instance` (e.g. `ErrorReportService.instance`, `MessageCache.instance`). Not freely instantiated services.

---

## Related files

- `lib/main.dart`
- `lib/src/features/model/main_screen.dart`
- `lib/src/features/screens/home_screen.dart`
- `lib/src/features/screens/admin/admin_dashboard_screen.dart`
- `lib/src/features/widgets/app_page_background.dart`, `post_card.dart`
- `lib/src/services/admin_service.dart`, `chat_service.dart`, `notification_service.dart`, `post_service.dart`
- `lib/src/providers/auth_providers.dart`, `admin_providers.dart`, `post_providers.dart`, `locale_provider.dart`
- `lib/src/l10n/app_strings.dart`, `strings_en.dart`
- `lib/src/theme/app_theme.dart`
