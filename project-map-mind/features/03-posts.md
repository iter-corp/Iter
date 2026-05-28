# Posts

## What this feature does
Posts are the core social object. They are created with `CreatePostScreen` (a single non-tab composer with a caption, optional place + city + GPS pin, multi-image gallery, and multi-video gallery — there is **no in-feed poll composer**; polls only exist inside chat threads, see `06-chat-and-messaging.md`). A post can carry up to 30 MB per video. The rendered card is `PostCard`, a 3 000+ line widget that handles single image, swipeable image carousel, inline auto-pause video (`_PostVideoPlayer` with visibility-driven play/pause), fullscreen viewer, double-tap-to-like heart burst, owner/viewer overflow menus, repost cluster, share-to-DM and share-to-story sheets, caption truncation + translation, and the "Discuss this post" entry point that promotes a feed post into a Q&A topic.

## Key screens / widgets
- [create_post_screen.dart](../../lib/src/features/screens/create_post_screen.dart) — composer (caption, place name + city + GPS pin via `LocationMap`, gallery / camera photo + video pickers, privacy chip).
- [post_detail_screen.dart](../../lib/src/features/screens/post_detail_screen.dart) — single-post route (used by deep links + notifications). Auto-opens `CommentScreen` modal sheet when `highlightCommentId` or `openComments` is passed.
- [post_card.dart](../../lib/src/features/widgets/post_card.dart) — every feed/travel/QA post tile. Embeds `_PostVideoPlayer`, `_FullscreenVideoScreen`, `_RepostBubbleCluster`, `_RepostBubble`, `_RepostMoreButton`, `_RepostUsersSheet`, `_RepostUserRow`, `_OwnerMenu`, `_ViewerMenu`, and the translate sheet.
- [poll_widgets.dart](../../lib/src/features/widgets/poll_widgets.dart) — `showCreatePollSheet(parentPath)` and rendering; `parentPath` is always `chats/{id}` or `eventChats/{id}` — polls are a chat feature, not a feed feature.

## Post "types"
There is no `postType` discriminator field. A post is what it carries:
- **Photo** — `imageUrls` non-empty (single image or carousel up to N images).
- **Video** — `videoUrls` non-empty. Inline player auto-plays only when visible (`VisibilityDetector` via `_PostVideoPlayer._onVisibilityChanged`) and auto-mutes / pauses when scrolled away.
- **Text-only** — caption with no media.
- **Discuss / Q&A** — same `posts/{id}` document with `discussKind` (`'question'`, etc.) and optionally `sourcePostId` linking back to the post it was created from. Counter-part `discussTopicId` is set on the source post once a topic exists.
- **Polls** — see `poll_widgets.dart`. Not a feed post type — created inside chats via `showCreatePollSheet(parentPath: 'chats/{id}' | 'eventChats/{id}')` and managed by `PollService`.

## Create-post flow (`CreatePostScreen._submit`)
1. `caption.trimRight()` (preserves leading content, trims trailing whitespace that would leave blank lines in the rendered card).
2. Refuse if caption + images + videos are all empty.
3. If a place name was typed without coordinates, attempt forward geocode via `geo.locationFromAddress("$placeName, $placeCity")`.
4. Upload each picked image via `StorageService.uploadPostImage`, then each video via `uploadPostVideo`. Videos are pre-validated against `_maxVideoBytes = 30 * 1024 * 1024`.
5. Call `PostService.createPost(caption, imageUrls, videoUrls, isPrivate, postPlaceName, postPlaceCity, postLat, postLng, postLocationExact)`.
6. `PostService.createPost` runs the caption through `ProfanityFilterService.findMatches`; matches throw `PostBlockedException` → composer surfaces the `createPostBlockedTitle/Body` dialog.
7. On success the route pops and a snackbar fires the localized "Published" toast.

## Place / location
- `_useCurrentLocationForPlace` grabs `Geolocator.getCurrentPosition` (medium accuracy) + reverse geocode to autofill place name and city. Sets `_placeFromCurrentLocation = true` which becomes `postLocationExact`.
- `_locateTypedPlaceOnMap` forward-geocodes the typed `place, city` string and drops a pin in `LocationMap` (`location_map.dart`).
- A post can have no place, a typed place without coordinates, or a place with coordinates (only those with coordinates appear in the Travel feed).

## Privacy
- `_isPrivate` chip toggles between `Public` and `Followers only`.
- **`_privacyDefaultApplied` one-shot guard**: if the user's `users/{uid}` doc has `isPrivate: true`, the first build of the composer flips the chip to followers-only automatically — but only once, so the user can still tap to switch a specific post back to Public.

## Post actions (in `PostCard`)
- **Like** — `PostService.toggleLike(postId)`. Optimistic, with a double-tap-to-like animated heart burst over the media. Double-tap on an already-liked post still plays the animation (no toggle off).
- **Comment** — opens `CommentScreen` modal sheet.
- **Share** — `_openShareSheet` opens a bottom sheet with two paths:
  - `_shareToStory` — adds the post as a story carrying `sharedPostId` (see `05-stories.md`).
  - `_shareAs(target)` — DM-share via chat, sets `sharedPostId` on the message.
- **Save** — `PostService.toggleSave(postId)` writes/removes `users/{uid}/saved/{postId}`.
- **Repost** — gated by `adminConfigProvider.repostsEnabled`. Toggles `users/{uid}/reposts/{postId}`. `_RepostBubbleCluster` shows up to ~3 follower-avatars who reposted; `_RepostMoreButton` opens `_RepostUsersSheet`.
- **Report** (`_ViewerMenu._report`) — 7 hardcoded reasons (`Spam or scam`, `Harassment or bullying`, `Hate speech`, `Violence or threats`, `Nudity or sexual content`, `Misinformation`, `Something else`) plus optional details. Calls `PostService.reportPost`, written to `postReports/{reportId}`.
- **Discuss this post** (`discussPost`) — if `post.discussTopicId == null` and `findDiscussTopicForPost` returns null, prompts via `_askDiscussQuestion` sheet, calls `PostService.createQaPostFromPost(post, question:)`, navigates to `QaThreadScreen`. If a topic already exists the menu shows "View in Discuss" and just navigates.
- **Owner menu** (`_OwnerMenu`): Edit caption (`_edit`), toggle visibility (`_toggleVisibility`), Save, Delete (`_delete` shows confirmation), Discuss.

## Inline video player (`_PostVideoPlayer`)
- Lazy controller. URL → `VideoPlayerController.networkUrl`. Local file (used by composer preview) → `VideoPlayerController.file`.
- `VisibilityDetector` auto-plays when ≥ some fraction visible, auto-pauses when scrolled off.
- Controls fade in on tap, auto-hide after a delay (`_scheduleHide`).
- Fullscreen via `_FullscreenVideoScreen` with optional landscape orientation lock (`_toggleLandscape`).

## Caption translation
- Inline translate icon in `_showFullCaption` modal calls `_translateCaption` which uses the translate service; a separate `_translated` field holds the result and a language selector lets the user retry with another target.

## Profanity / blocked words
- `PostService.createPost` runs caption through `ProfanityFilterService.findMatches` and throws `PostBlockedException(matchedWords)` on hit. The composer shows a generic blocked dialog (does not list matched words to the user).
- `createQaPost` does the same and throws `DiscussPostBlockedException`.

## Firestore collections touched
- `posts/{postId}` — main post doc (`authorUid`, `authorUsername`, `authorAvatar`, `caption`, `imageUrls`, `videoUrls`, `likesCount`, `commentsCount`, `isPrivate`, `createdAt`, `postPlaceName`, `postPlaceCity`, `postLocation:{lat,lng}`, `postLocationExact`, `discussKind`, `discussTopicId`, `sourcePostId`).
- `posts/{postId}/comments` (read for delete-cascade in `PostService`).
- `users/{uid}` — author profile, counters, following.
- `users/{uid}/saved/{postId}` — saved bookmark.
- `users/{uid}/reposts/{postId}` — repost record.
- `users/{uid}/following` — used for `_RepostBubbleCluster` priority.
- `postReports/{reportId}` — moderation queue.
- `discussReports/{reportId}` — moderation queue for QA posts.

## Services used
- [post_service.dart](../../lib/src/services/post_service.dart) — `createPost`, `createQaPost`, `createQaPostFromPost`, `findDiscussTopicForPost`, `getPostById`, `toggleLike`, `toggleSave`, `reportPost`, `searchTravelPlaces`, `qaPostsWithMatchingAnswer`.
- [storage_service.dart](../../lib/src/services/storage_service.dart) — `uploadPostImage`, `uploadPostVideo`.
- [profanity_filter_service.dart](../../lib/src/services/profanity_filter_service.dart) — blocked-words check.
- [city_service.dart](../../lib/src/services/city_service.dart) — autocomplete for the City field (warmed via `worldCitiesProvider`).
- [translate_service.dart](../../lib/src/services/translate_service.dart) — caption translation.

## Non-obvious business rules
- Videos > 30 MB are rejected client-side (`_ensureVideoUnderLimit`).
- Trailing whitespace is trimmed from captions on submit — without this, trailing newlines render as visible blank lines in the feed.
- Private-account posts default to followers-only, but the chip can still be toggled per-post (one-shot guard).
- Geocoding failures during submit are silently swallowed — the post is still created without coordinates (it just won't appear in Travel).
- The composer warms the `worldCitiesProvider` future on init so the city picker opens instantly.
- Camera-story import (`camera_story_screen.dart`) is imported in `create_post_screen.dart` but only referenced as a navigation target — composer itself uses `image_picker` for both camera and gallery.
- `discussPost` first checks `post.discussTopicId`, then falls back to `findDiscussTopicForPost` (server lookup) before creating a new topic — prevents duplicates if `discussTopicId` is stale.
- The repost cluster prioritizes follower-uids before falling back to recent reposters.

## Localization
- `create_post_screen.dart`: ~32 `context.t.*` calls.
- `post_card.dart`: ~45 `context.t.*` calls.
- `post_detail_screen.dart`: ~2 keys.

## Related files
- `lib/src/features/screens/create_post_screen.dart`
- `lib/src/features/screens/post_detail_screen.dart`
- `lib/src/features/widgets/post_card.dart`
- `lib/src/features/widgets/poll_widgets.dart`
- `lib/src/features/widgets/location_map.dart`
- `lib/src/features/model/post_model.dart`
- `lib/src/services/post_service.dart`
- `lib/src/services/storage_service.dart`
- `lib/src/services/profanity_filter_service.dart`
- `lib/src/services/poll_service.dart`
- `lib/src/services/translate_service.dart`
- `lib/src/providers/post_providers.dart`
- `lib/src/providers/poll_providers.dart`
