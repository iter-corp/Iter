# Tech Stack

Flutter package name `coil`, version `1.1.1+2`, Dart SDK `>=3.0.0 <4.0.0` ([`pubspec.yaml:1-7`](../../pubspec.yaml)).

## Flutter & Dart base

| Package | Version | Purpose |
|---|---|---|
| `flutter` (sdk) | bundled | Flutter framework. |
| `flutter_localizations` (sdk) | bundled | Material/Cupertino localized widgets + RTL machinery. |

## State management

| Package | Version | Purpose |
|---|---|---|
| `flutter_riverpod` | `^2.5.1` | App-wide state container; every provider in [`lib/src/providers/`](../../lib/src/providers) is a Riverpod provider. |
| `rxdart` | `^0.28.0` | `Rx.combineLatest*` and `onErrorReturn` used to merge feed + follow + block streams ([`lib/src/providers/post_providers.dart:57-69`](../../lib/src/providers/post_providers.dart)). |

## Navigation

| Package | Version | Purpose |
|---|---|---|
| `go_router` | `^13.2.0` | Declarative routing with auth/onboarding redirect logic ([`lib/src/router/app_router.dart`](../../lib/src/router/app_router.dart)). |

## Firebase services

| Package | Version | Purpose |
|---|---|---|
| `firebase_core` | `^3.6.0` | App initialization in [`lib/main.dart:67`](../../lib/main.dart). |
| `firebase_auth` | `^5.7.0` | Email/password, Google, Apple sign-in ([`lib/src/services/auth_service.dart`](../../lib/src/services/auth_service.dart)). |
| `google_sign_in` | `^6.2.2` | Google OAuth provider for `firebase_auth`. |
| `sign_in_with_apple` | `^7.0.1` | Apple ID sign-in. |
| `cloud_firestore` | `^5.6.12` | Primary datastore: posts, users, chats, events, notifications. |
| `firebase_storage` | `^12.4.10` | Legacy `avatars/{uid}` and `posts/{uid}` paths ([`storage.rules`](../../storage.rules)). New media goes to Supabase. |
| `cloud_functions` | `^5.1.5` | Calls callable functions exported from [`functions/src/index.ts`](../../functions/src/index.ts) (translate, live tokens, fan-out). |
| `firebase_messaging` | `^15.2.0` | Push notifications + tap routing ([`lib/src/services/fcm_service.dart`](../../lib/src/services/fcm_service.dart)). |
| `firebase_database` | `^11.1.4` | Realtime Database for presence and typing ([`lib/src/services/presence_service.dart`](../../lib/src/services/presence_service.dart), [`lib/src/services/typing_service.dart`](../../lib/src/services/typing_service.dart)). |

## Live media

| Package | Version | Purpose |
|---|---|---|
| `agora_rtc_engine` | `^6.3.2` | Real-time audio/video broadcasts; token issued by [`functions/src/live.ts`](../../functions/src/live.ts). |

## Media capture & playback

| Package | Version | Purpose |
|---|---|---|
| `image_picker` | `^1.1.2` | Gallery/camera image picking. |
| `photo_manager` | `^3.6.0` | Gallery enumeration for the in-app picker grid. |
| `camera` | `^0.11.0+2` | Custom camera UI used for story capture ([`lib/src/features/screens/camera_story_screen.dart`](../../lib/src/features/screens/camera_story_screen.dart)). |
| `gal` | `^2.3.1` | Saves captured media back to the device gallery. |
| `speech_to_text` | `^7.0.0` | Voice → text in Translate tab and voice-message live transcript. |
| `flutter_tts` | `^4.2.5` | Text → speech for Translate. |
| `record` | `^5.1.2` | Records voice messages for chat. |
| `audioplayers` | `^6.1.0` | Plays voice messages. |
| `video_player` | `^2.9.1` | Inline video playback in posts/stories/chat. |
| `flutter_native_video_trimmer` | `^1.1.9` | Trims video before posting. |
| `visibility_detector` | `^0.4.0+2` | Detects whether a video is on-screen so feed videos auto-pause. |
| `file_picker` | `^8.1.2` | Picks documents/files for chat attachments. |
| `open_filex` | `^4.5.0` | Opens downloaded chat files in OS viewer. |
| `path_provider` | `^2.1.4` | Resolves cache/temp/documents directories for downloads and the message cache. |

## UI / media presentation

| Package | Version | Purpose |
|---|---|---|
| `cached_network_image` | `^3.3.1` | Network image caching for avatars and post media. |
| `flutter_cache_manager` | `^3.3.1` | Disk-cache backing for large post images and post videos. |
| `flutter_native_splash` | `^2.4.0` | Native splash screen config. |
| `flutter_svg` | `^2.2.4` | SVG nav icons in [`assets/icons/`](../../assets/icons) (`Home.svg`, `Event.svg`, `Translate.svg`, `Message.svg`, `Profile.svg`). |

## Location & maps

| Package | Version | Purpose |
|---|---|---|
| `geolocator` | `^13.0.1` | GPS lookup for the "Nearby" / Connect tab. |
| `geocoding` | `^3.0.0` | Reverse-geocodes coords to city/country during onboarding. |
| `flutter_map` | `^7.0.2` | OpenStreetMap-based maps (event detail / location picker — [`lib/src/features/widgets/location_map.dart`](../../lib/src/features/widgets/location_map.dart)). |
| `latlong2` | `^0.9.1` | Lat/long primitives consumed by `flutter_map`. |
| `country_state_city` | `^0.1.6` | Country/city pickers in profile/onboarding. |

## Networking & config

| Package | Version | Purpose |
|---|---|---|
| `http` | `^1.2.2` | Direct HTTP calls to Supabase edge functions and signed-upload URLs ([`lib/src/services/storage_service.dart`](../../lib/src/services/storage_service.dart)). |
| `flutter_dotenv` | `^5.2.1` | Loads `.env` at boot ([`lib/main.dart:60`](../../lib/main.dart)) — used for `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `USE_FIREBASE_EMULATOR`, `FIREBASE_EMULATOR_HOST`. |
| `url_launcher` | `^6.3.1` | Opens external URLs (event links, social handles, "open in maps"). |
| `share_plus` | `^10.1.2` | OS share-sheet for posts / app links. |

## Localization helpers

| Package | Version | Purpose |
|---|---|---|
| `intl` | `^0.20.2` | Date / number formatting in feed timestamps and event dates. |
| `diacritic` | `^0.1.6` | Strips accents for case/locale-insensitive search (e.g. username match). |

## Device & platform utilities

| Package | Version | Purpose |
|---|---|---|
| `permission_handler` | `^11.3.1` | Runtime permission prompts for camera/mic/storage/location. |
| `shared_preferences` | `^2.3.2` | Persistent key-value store for theme + locale ([`lib/src/providers/theme_provider.dart`](../../lib/src/providers/theme_provider.dart), [`lib/src/providers/locale_provider.dart`](../../lib/src/providers/locale_provider.dart)). |
| `package_info_plus` | `^8.0.0` | Reads installed app version for the version gate ([`lib/main.dart:370`](../../lib/main.dart)). |
| `crypto` | `^3.0.7` | SHA-256 hashing (used in Apple sign-in nonce — [`lib/src/services/auth_service.dart`](../../lib/src/services/auth_service.dart)). |

## Dependency overrides

| Package | Version | Reason ([`pubspec.yaml:84-88`](../../pubspec.yaml)) |
|---|---|---|
| `record_linux` | `^1.1.0` | `record 5.1.2` transitively pulls `record_linux 0.7.2`, which is incompatible with `record_platform_interface 1.5.0`. Pinning to 1.x fixes the iOS compile error. |

## Dev dependencies

| Package | Version | Purpose |
|---|---|---|
| `flutter_test` (sdk) | bundled | Widget/unit testing. |
| `flutter_lints` | `^3.0.0` | Standard Flutter lint set. |

## Assets

Declared in [`pubspec.yaml:102-105`](../../pubspec.yaml):

```
.env
assets/img/
assets/icons/
```

The commented-out Inter font block (lines 107-117) means the app currently uses the platform default fonts. No custom fonts are bundled.

## Android native config

[`android/app/build.gradle.kts`](../../android/app/build.gradle.kts):

- `namespace` and `applicationId` = `com.iter.ai`
- `compileSdk` / `minSdk` / `targetSdk` / `versionCode` / `versionName` all inherited from the Flutter Gradle plugin (`flutter.*` properties).
- Java/Kotlin target: `JavaVersion.VERSION_11`.
- Plugins: `com.android.application`, `com.google.gms.google-services` (FlutterFire), `kotlin-android`, `dev.flutter.flutter-gradle-plugin`.
- Release build currently signed with debug keys (TODO marker on line 38).

## iOS native config

[`ios/Runner/Info.plist`](../../ios/Runner/Info.plist):

- Display name and bundle name: `Iter`.
- Scene-based app lifecycle (`UIApplicationSceneManifest`, `SceneDelegate.swift`).
- URL scheme registered for Google sign-in: `com.googleusercontent.apps.751233585713-tgffet0qbu9em9mlhsbh84jiqrh24a8o` (line 69).
- Background modes: `remote-notification` (FCM).
- `FirebaseAppDelegateProxyEnabled = true`.
- Permission usage strings for camera, microphone, speech recognition, photo library (read + add), location-when-in-use — all under the "Iter" brand.
- Supports portrait + both landscape orientations (iPhone) and all four orientations (iPad).
- `GoogleService-Info.plist` present at [`ios/Runner/GoogleService-Info.plist`](../../ios/Runner/GoogleService-Info.plist).

## Cloud Functions backend (Node, separate package)

[`functions/package.json`](../../functions/package.json):

- Node 20.
- `firebase-functions ^5.1.1`, `firebase-admin ^12.7.0`.
- `@google-cloud/translate ^8.5.0` (server-side translate).
- `agora-access-token ^2.0.4` (mint live-stream tokens).
- TypeScript build with `tsc`. Modules exported: `adminUsers`, `comments`, `events`, `follows`, `likes`, `live`, `messages`, `notifications`, `posts`, `translate` ([`functions/src/index.ts:16-27`](../../functions/src/index.ts)).
- Maintenance scripts: `seed:profanity`, `backfill:message-visibility`.

## Related files

- [`pubspec.yaml`](../../pubspec.yaml)
- [`android/app/build.gradle.kts`](../../android/app/build.gradle.kts)
- [`ios/Runner/Info.plist`](../../ios/Runner/Info.plist)
- [`functions/package.json`](../../functions/package.json)
- [`functions/src/index.ts`](../../functions/src/index.ts)
- [`lib/main.dart`](../../lib/main.dart)
