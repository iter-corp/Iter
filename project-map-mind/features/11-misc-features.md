# Misc Features

Smaller utility screens that aren't large enough to warrant their own doc but still ship in the app. Each section below documents one screen.

---

## Translate screen

### What this feature does
A standalone translation surface (`TranslateBody`) reachable from the bottom nav. Source language and target language are picker chips backed by the shared `kTranslateLanguages` list in `translate_service.dart`. Supports voice input (`speech_to_text`), TTS playback (`flutter_tts`), copy-to-clipboard, swap-languages, and save-to-history. Gated by `adminConfigProvider.translateEnabled` — falls back to `FeatureDisabledView` when off.

### Key fields
- `_sourceLang` defaults to `English (USA)`, `_targetLang` defaults to `Kurdish (Sorani)`.
- Voice input uses `stt` with localized error strings (`translateSttNoMatch`).
- Saved translations write to `savedTranslations` (per-user via subcollection on the user doc).

### Files
- [translate_screen.dart](../../lib/src/features/screens/translate_screen.dart) (~902 lines, 11 `context.t.*` keys).
- [translate_service.dart](../../lib/src/services/translate_service.dart).
- [feature_disabled_view.dart](../../lib/src/features/widgets/feature_disabled_view.dart).

---

## Saved translations

### What this feature does
Browse + delete previously saved translations. Lists every `SavedTranslation` doc under `users/{uid}/savedTranslations` ordered by `createdAt desc`. Each tile shows `sourceText` (truncated) + `translatedText` and a delete swipe / button. Empty state surfaces `savedTranslationsEmpty`. Unauthenticated viewers see `savedTranslationsSignInPrompt`.

### Files
- [saved_translations_screen.dart](../../lib/src/features/screens/saved_translations_screen.dart) (~230 lines, 4 `context.t.*` keys).

### Firestore touched
- `users/{uid}/savedTranslations/{id}` — `sourceText`, `translatedText`, `sourceLang`, `targetLang`, `createdAt`.

---

## Contact us

### What this feature does
Submit help / feedback to admins and chat with them. Two surfaces in one screen (`ContactUsScreen`):
1. The user's existing threads list (`myContactRequestsProvider`).
2. A "+" → `_NewRequestScreen` composer that picks `ContactRequestType` (`message`, `bug`, `feedback`, etc.) and writes a first message.

Each thread becomes a `ContactRequest` doc with status `open` / `in_progress` / `closed`. Admins reply through `AdminContactRequestsScreen`. Replies render inline so the screen behaves like a slim 1:1 chat.

### Files
- [contact_us_screen.dart](../../lib/src/features/screens/contact_us_screen.dart) (~986 lines, 56 `context.t.*` keys).
- [contact_request_service.dart](../../lib/src/services/contact_request_service.dart).
- [contact_request_providers.dart](../../lib/src/providers/contact_request_providers.dart).

### Firestore touched
- `contactRequests/{id}` — main doc.
- `contactRequests/{id}/messages` — thread messages.

---

## Request screen (chat requests / hidden chats)

### What this feature does
**Not the contact-us screen.** Despite the name, `request_screen.dart` houses `HiddenRequestsScreen` (chats the user explicitly hid) and `RequestsTab` (the Requests tab content for `MessageScreen` — chats from people not in the user's mutual-follow circle, waiting on accept). Tiles render with `_UnreadCountBadge` and tap into `ChatScreen`.

### Files
- [request_screen.dart](../../lib/src/features/screens/request_screen.dart) (~209 lines, 8 `context.t.*` keys).

### Firestore touched
- `chats/{chatId}` — `acceptedBy`, `hiddenForUids`, `participants`.

---

## Chat media gallery

### What this feature does
Per-chat media browser (`ChatMediaScreen`). Reached from the chat header info icon. Four tabs over the chat's messages stream:
- **Images** — grid of every photo.
- **Files** — every document/file attachment.
- **Voices** — every voice note.
- **Links** — every URL extracted from message text via `_extractLinks(msgs)`.

Tapping an image opens `ImageViewerScreen` (zoomable, save to gallery). Files open via `open_filex`. Voices use the chat-bubble voice player. Links open in the system browser.

### Files
- [chat_media_screen.dart](../../lib/src/features/screens/chat_media_screen.dart) (~966 lines, 31 `context.t.*` keys).

### Services used
- `gal` — save image to system photo library.
- `open_filex` — open downloaded files.
- `path_provider` — temp directory for downloads.
- `http` — fetch the remote URL before saving.

---

## Image viewer

### What this feature does
Fullscreen zoomable image viewer (`ImageViewerScreen`) for post images, story replies, profile avatar / cover taps. Saves to the device photo gallery via `gal` (`gal.putImage`), surfaces `savedToGallery` / `saveFailed(e)` toasts. PageView between multiple images. Tap-to-dismiss.

### Files
- [image_viewer_screen.dart](../../lib/src/features/screens/image_viewer_screen.dart) (~169 lines, 3 `context.t.*` keys).

### Permissions
- iOS: `NSPhotoLibraryAddUsageDescription`.
- Android 10+: scoped storage; gal handles the bridge.

---

## Language picker

### What this feature does
Full-screen language picker (`LanguageScreen`) reachable from Settings → Language. Iterates `AppLanguage.values` (the in-app supported locales — `en`, `ar`, `ckb`) and lets the user select one. Selection calls `localeProvider.notifier.setLanguage(lang)` and `MaterialApp.locale` rebuilds the whole app — including text direction (LTR ↔ RTL). Each tile shows the language's two-letter code badge, `nativeName` (in its own script), and `englishName`.

### Files
- [language_screen.dart](../../lib/src/features/screens/language_screen.dart) (~113 lines, 2 `context.t.*` keys).
- [locale_provider.dart](../../lib/src/providers/locale_provider.dart) — `localeProvider`, `AppLanguage` enum.

### Non-obvious rule
The picker uses `flexibleSpace: AppPageBackground` so the gradient survives the app-bar's transparency. Switching language fires a floating snackbar with `languageChanged`.

---

## Related files (shared)
- `lib/src/services/translate_service.dart` — `kTranslateLanguages`, `TranslateService.translateText`.
- `lib/src/providers/locale_provider.dart` — `localeProvider`, `AppLanguage`.
- `lib/src/providers/preferred_language_provider.dart` — per-user preferred translation target.
- `lib/src/features/widgets/feature_disabled_view.dart` — shared "feature disabled by admin" view.
- `lib/src/features/widgets/app_page_background.dart` — gradient wallpaper used by most of these screens.
