# COIL — Features & Technologies

A social community application with multi-language support, real-time chat, events, stories, live audio/video, and admin moderation tools.

---

## 1. Core Technologies

### Frontend (Mobile / Cross-platform)
- **Flutter** (SDK ^3.0.0) — single codebase for Android, iOS, Web, Windows, macOS, Linux.
- **Dart** — primary language.
- **Riverpod** (`flutter_riverpod ^2.5.1`) — state management.
- **RxDart** — reactive streams.
- **go_router ^13.2.0** — declarative navigation.
- **flutter_localizations** + custom `app_strings.dart` — i18n with manual string tables (English, Arabic, Kurdish/Sorani).
- **Material Design** UI.

### Backend
- **Firebase Cloud Functions** (Node.js 20, TypeScript) — serverless API layer.
- **Cloud Firestore** — primary NoSQL database (posts, users, chats, events, comments, etc.).
- **Firebase Realtime Database** — presence (online/offline) and typing indicators.
- **Firebase Authentication** — email/password (with `sendEmailVerification` link), Google Sign-In, Apple Sign-In.
- **Firebase Cloud Storage** — media storage for some assets.
- **Firebase Cloud Messaging (FCM)** — push notifications.
- **Supabase Edge Functions** (`issue-upload-url`) — issues signed upload URLs for large media (posts, stories, videos), with RLS policies (`rls_policies.sql`).
- **Google Cloud Translate API** (`@google-cloud/translate`) — server-side translation.
- **Agora RTC** (`agora_rtc_engine` + `agora-access-token`) — live audio/video rooms; tokens issued by Cloud Function.

### Security
- **Firestore Security Rules** (`firestore.rules`) — role-based access (`isAdmin`, `isOrgAdmin`), privacy-aware reads (`canSeeContent`), chat-participant gating, document-shape validation for unauthenticated error-report writes.
- **Realtime DB rules** (`database.rules.json`) — presence & typing channels scoped to authenticated users.
- **Supabase RLS policies** (`supabase/rls_policies.sql`) — public read on storage buckets; writes only via `service_role` key used by the edge function, which verifies a Firebase ID token before signing upload URLs.
- **Server-authoritative Cloud Functions** — likes, follows, comments, and notifications go through Cloud Functions, so clients cannot fabricate counts or fan-outs.
- **Apple Sign-In nonce** — `crypto` package used to SHA-256 hash the nonce passed to `SignInWithApple.getAppleIDCredential` (`auth_service.dart`).
- **Profanity filter + moderation flags** on messages and posts (`profanity_filter_service.dart`).
- **Block / blacklist** system (`block_service.dart`, admin blacklist screen).

### Build / DevOps
- **Firebase CLI** (`firebase.json`) for deploys.
- **TypeScript ^5.6.3** for Cloud Functions.

---

## 2. User-Facing Features

### Authentication
- Email/password sign-up and login.
- Google Sign-In (`google_sign_in`).
- Apple Sign-In (`sign_in_with_apple`) with SHA-256 hashed nonce.
- Email verification via `FirebaseAuth.sendEmailVerification` (triggered from profile settings).
- Forgot-password / password-reset flow.
- Change-password screen.
- Onboarding flow with location permission and "Nearby" detection.
- Splash screen with native splash (`flutter_native_splash`).

### Home Feed & Posts
- Scrollable post feed (`home_screen.dart`, `post_card.dart`).
- Create posts with text, images, and video (`create_post_screen.dart`).
- Post detail with comments (`post_detail_screen.dart`).
- Likes (Cloud Function `likes.ts`).
- Comments with threading (`comment_screen.dart`, `comments.ts`).
- Polls inside posts (`poll_widgets.dart`, `poll_service.dart`).
- Q&A threads (`qa_thread_screen.dart`).
- Profanity filtering (`profanity_filter_service.dart`).
- Image viewer with zoom (`image_viewer_screen.dart`).
- Cached image/video playback (`cached_network_image`, `flutter_cache_manager`, `video_player`, `visibility_detector`).

### Stories
- Camera capture for stories (`camera_story_screen.dart`, `camera` package).
- Add to existing story (`add_to_story_screen.dart`).
- Story preview before publishing (`story_preview_screen.dart`).
- Story viewer with progress bars (`story_viewer_screen.dart`).
- Sticker picker (`sticker_picker_sheet.dart`, `sticker_service.dart`).
- Story section on home feed (`story_section.dart`, `story_item.dart`).
- Story comments (`story_comment_model.dart`).

### Messaging / Chat
- 1:1 direct messages (`chat_screen.dart`, `message_widget.dart`).
- Group chats with settings (`group_settings_screen.dart`, `create_group_sheet.dart`).
- Message reactions (`message_reactions_bar.dart`, `reaction_service.dart`).
- Typing indicators (`typing_service.dart`, Realtime DB).
- Presence — online/offline status (`presence_service.dart`, Realtime DB).
- Voice messages — record + playback (`record`, `audioplayers`).
- Media in chats — images, videos, files (`chat_media_screen.dart`, `file_picker`, `open_filex`).
- Message cache (`message_cache.dart`) for offline reading.
- Message list (`message_screen.dart`).

### Events
- Browse events (`event_screen.dart`).
- Event detail (`event_detail.dart`).
- Event registration flow (`event_registration_sheet.dart`, `event_registration_service.dart`).
- Event group chat (`event_chat_screen.dart`, `event_chat_service.dart`).
- Event group settings (`event_group_settings_screen.dart`).
- Event-specific notification settings (`event_notifications_settings_screen.dart`).
- Unavailable-event view (`event_unavailable_screen.dart`).
- Cloud Function backend (`events.ts`).

### Live (Audio/Video Rooms)
- Agora-powered live rooms (`agora_rtc_engine`).
- Live token issuance via Cloud Function (`live.ts` → `issueLiveToken`).
- Host vs audience roles.

### Translation
- In-app translation screen (`translate_screen.dart`).
- Saved translations (`saved_translations_screen.dart`).
- Server-side translate Cloud Function (`translate.ts` using Google Cloud Translate).
- Speech-to-text input (`speech_to_text`).
- Text-to-speech output (`flutter_tts`).
- User's preferred language (`preferred_language_provider.dart`).

### Profile
- View own / other users' profiles (`profile_screen.dart`, `user_screen.dart`, `profile_widget.dart`, `user_profile_widget.dart`).
- Edit profile (`edit_profile.dart`).
- Profile settings (`profile_settings_screen.dart`).
- Profile visitors list — see who viewed your profile (`profile_visitors_screen.dart`, `profile_visitor_service.dart`).
- Follow / unfollow (`follow_service.dart`, `follows.ts`).
- Block users (`block_service.dart`).
- Personalization fields (`personalization_fields.dart`).

### Notifications
- Push notifications via FCM (`fcm_service.dart`, `firebase_messaging`).
- In-app notifications list (`notification_screen.dart`, `notification_tile.dart`).
- Notification permission handling (`permission_handler`).
- Cloud Function dispatcher (`notifications.ts`).

### Location & Maps
- GPS / current location (`geolocator`).
- Reverse-geocoding (`geocoding`).
- Map display (`flutter_map`, `latlong2`).
- Open external map links (`maps_links.dart`, `url_launcher`).
- Country/State/City picker (`country_state_city`).
- Location map widget (`location_map.dart`).

### Settings & Misc
- Language switcher (`language_screen.dart`, `locale_provider.dart`) — English / Arabic / Kurdish (Sorani) with custom CKB Material localizations.
- Theme provider (`theme_provider.dart`, `app_theme.dart`).
- Contact us (`contact_us_screen.dart`, `contact_request_service.dart`).
- Request screen (`request_screen.dart`).
- App share (`share_app.dart`, `share_plus`).
- Save media to gallery (`gal`).
- Photo picking from gallery (`image_picker`, `photo_manager`).
- App version info (`package_info_plus`).
- Persistent prefs (`shared_preferences`).
- Diacritic-insensitive search (`diacritic`).
- Responsive layout helper (`responsive.dart`).

---

## 3. Admin Features

Found in [frontend/lib/src/features/screens/admin/](frontend/lib/src/features/screens/admin/) and [functions/src/adminUsers.ts](functions/src/adminUsers.ts).

- **Admin dashboard** (`admin_dashboard_screen.dart`) — overview.
- **User management** (`admin_users_screen.dart`) — admin actions on users via `adminUsers.ts` Cloud Function.
- **Posts moderation** (`admin_posts_screen.dart`).
- **Discussion posts moderation** (`admin_discuss_posts_screen.dart`).
- **Events admin** (`admin_events_screen.dart`).
- **Reports center** (`admin_reports_screen.dart`, `admin_reports_toolbar.dart`):
  - Post reports (`admin_post_reports_screen.dart`).
  - User reports (`admin_user_reports_screen.dart`).
  - Discussion reports (`admin_discuss_reports_screen.dart`).
  - Error reports (`admin_error_reports_screen.dart`, `error_report_service.dart`).
- **Blacklist** (`admin_blacklist_screen.dart`).
- **Contact requests** (`admin_contact_requests_screen.dart`).
- **Admin settings** (`admin_settings_screen.dart`).
- Admin notifications provider (`admin_report_notifications_provider.dart`).

---

## 4. Cloud Functions (Server-side)

Defined in [functions/src/](functions/src/):

| File | Responsibility |
|------|----------------|
| `adminUsers.ts` | Admin user management endpoints. |
| `comments.ts` | Comment creation, counters, notifications. |
| `events.ts` | Event lifecycle. |
| `follows.ts` | Follow/unfollow, follower counters. |
| `likes.ts` | Like toggles and counters. |
| `live.ts` | Issues Agora RTC tokens (`issueLiveToken`). |
| `messages.ts` | Chat message hooks. |
| `notifications.ts` | Push-notification fan-out via FCM. |
| `posts.ts` | Post lifecycle. |
| `translate.ts` | Google Cloud Translate proxy. |

Plus scripts:
- `scripts/seed-profanity.js` — seeds profanity word list.
- `scripts/backfill-message-visibility.js` — one-off backfill.

---

## 5. Supabase Layer

- **`supabase/functions/issue-upload-url`** — Edge Function that returns short-lived signed upload URLs for the Flutter client to PUT media directly to Supabase Storage (bypassing Firebase Storage egress).
- **`supabase/rls_policies.sql`** — Row-Level-Security policies for the Supabase buckets/tables.
- Client uses plain `http` package + `flutter_dotenv` for secret config.

---

## 6. Supported Platforms

Per the Flutter project layout — Android, iOS, Web, Windows, macOS, Linux.

---

## 7. Languages (i18n)

- English (`strings_en.dart`)
- Arabic (`strings_ar.dart`)
- Kurdish — Sorani (`strings_ckb.dart`) with custom `ckb_material_localizations.dart` because Flutter ships no built-in Kurdish localization.
