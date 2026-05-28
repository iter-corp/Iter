# Stories

## What this feature does
Stories are 24-hour ephemeral posts shown as a horizontal avatar strip at the top of the home feed (`StoriesList` in `story_section.dart`). They support **three media kinds** stored in the same `stories/{storyId}` doc and discriminated by which fields are populated: **image** (`imageUrl`), **video** (`videoUrl` + optional trim window), **text-only** (`textContent` + `backgroundColor` + `textColor` + optional shape). Stories can also carry a `sharedPostId` linking back to a feed post, in which case the viewer renders the post as an embedded card. Each story optionally has free-form `StoryTextOverlay` items (positioned, rotated, scaled text with background style — burned into image stories at compose time, kept as structured data on video stories since the bytes can't be edited). The viewer (`StoryViewerScreen`) is the full-screen interactive surface: tap to advance, long-press to pause, swipe down to dismiss, swipe sideways to jump between authors, and DM-reply text input at the bottom.

## Key screens / widgets
- [story_section.dart](../../lib/src/features/widgets/story_section.dart) — `StoriesList` horizontal strip + `_MyStoryBubble` + `_StoryBubble`. Groups by `authorUid`, sorts unseen-first, owner-bubble pinned leftmost.
- [story_item.dart](../../lib/src/features/widgets/story_item.dart) — small placeholder bubble component (only used by the loading skeleton).
- [story_viewer_screen.dart](../../lib/src/features/screens/story_viewer_screen.dart) — 2700-line full-screen viewer. Holds the progress bar, video controller, long-press pause, DM reply composer, quick-reactions row, likers / viewers pills + sheets, share sheet (`_StoryShareSheet`).
- [story_preview_screen.dart](../../lib/src/features/screens/story_preview_screen.dart) — image story composer. Renders the image + draggable/pinch-rotatable `_StoryTextOverlay`s, captures the composite via `RenderRepaintBoundary.toImage` at publish time so the overlays are burned in.
- [text_story_composer_screen.dart](../../lib/src/features/screens/text_story_composer_screen.dart) — text-only composer. Cycles through background-color `_presets`, types content, publishes.
- [camera_story_screen.dart](../../lib/src/features/screens/camera_story_screen.dart) — live camera (front/back swap, photo + video capture via `camera` package), with `image_picker` fallback for gallery video.
- [add_to_story_screen.dart](../../lib/src/features/screens/add_to_story_screen.dart) — system photo / video picker grid (`photo_manager`).
- [video_story_preview_screen.dart](../../lib/src/features/screens/video_story_preview_screen.dart) — video preview + dual-handle trim bar (`_TrimBar`). Cap: **30 s**, **30 MB**; trim is metadata-only by default (`videoTrimStartMs` / `videoTrimEndMs`), with `_shouldExportVideo` triggering a real re-encode via `flutter_native_video_trimmer` only when the trimmed segment would still exceed 30 MB.
- [story_text_overlay.dart](../../lib/src/features/widgets/story_text_overlay.dart) — `StoryTextOverlay` model + JSON encoding + `StoryOverlayWidget` (pan / pinch / rotate / double-tap-to-edit). Background styles: `none`, `rounded`, `box`, `outline`, `pill`, `brush`.

## Story types
- **Image** — `imageUrl` set, no video, no text content. Composer is `StoryPreviewScreen`.
- **Video** — `videoUrl` set; `imageUrl` may carry a thumbnail used in story bubbles. Trim is stored as `videoTrimStartMs` / `videoTrimEndMs` and **clamped client-side in the viewer** rather than re-encoded.
- **Text-only** — `textContent` non-empty, `imageUrl` empty, no `videoUrl`, no `sharedPostId`. Renders `textContent` on solid `backgroundColor` with `textColor` and a `textBorderStyle` shape.
- **Shared post** — any story type with `sharedPostId` set; the viewer renders the post card (`_SharedPostStoryView`) on a background instead of media.

## Story strip ordering (`StoriesList`)
1. Owner's own bubble pinned first (with a `+` plus icon if they have no story yet → opens `AddToStoryScreen`).
2. Other authors sorted unseen-first; within the same seen-state, the author with the newest story comes first.
3. `_seenByAuthor` is computed asynchronously by combining `locallyViewedStoryIdsProvider` and `StoryService.hasViewed` per-story checks. An author is "seen" only if **every** one of their active stories has been viewed.
4. `allGroups` is a stable list used by the viewer to swipe between authors.

## Story viewer behaviors (`StoryViewerScreen`)
- **Tap to advance** — left/right edge taps jump back/forward. Suppressed while the reply input has focus or holds text.
- **Long-press to pause** — pauses the progress bar AND the underlying `VideoPlayer`. Released → resume from the saved position.
- **DM reply** — `_replyToStoryAsDM(text)` opens (or creates) a 1:1 chat with the author and sends the text plus a `sharedStoryId` and `imageUrl` so the message shows the story thumbnail. **Authors cannot reply to their own stories** (`if (author == me) skip`). Sign-in required; otherwise a `_StorySignInBanner` replaces the composer.
- **Quick reactions** — heart + emoji row. Tapping ❤ both fires the story like AND sends the reaction as a DM, in one action (per code: the heart pill was merged into the reactions row so the like and DM are unified). For all other emojis, only the DM is sent.
- **Likes / Views pills** — `_LikesPill`, `_ViewsPill` open `_LikersSheet` / `_ViewersSheet` (author-only views).
- **Share sheet** — `_StoryShareSheet` lets the author DM the story to recipients (`_StoryShareRecipientCard`) or share-to-system via `share_plus`.
- **Mark-as-seen** — on each entry, the local `locallyViewedStoryIdsProvider` is updated, the `viewers/{uid}` subdoc is written, and the owner's `OwnStorySeenService` is poked so the strip's seen indicator updates immediately.

## Video trim window
- `_maxStoryDuration = Duration(seconds: 30)`; `_maxStoryVideoBytes = 30 * 1024 * 1024`.
- Default trim window when loading a video: `[0, min(duration, 30s)]`.
- `_TrimBar` is dual-handle; dragging either handle updates `_trimStart` / `_trimEnd`; preview `_onTick` loops by seeking back to `_trimStart` once playback crosses `_trimEnd`.
- If the trimmed window still > 30 MB, `_shouldExportVideo` triggers a real `VideoTrimmer.trimVideo` via `flutter_native_video_trimmer` (90-s timeout); otherwise only `videoTrimStartMs` and `videoTrimEndMs` are persisted, no re-encode.

## Overlays
- 0..1 canvas-relative coordinates so layouts survive orientation changes.
- `StoryOverlayWidget` supports pan, pinch-scale (clamp 0.4 .. 5.0), rotate, double-tap to edit.
- Background styles: `none`, `rounded`, `box`, `outline`, `pill`, `brush` (custom `BrushBackground` painter).
- For image stories, the publish step uses `RenderRepaintBoundary` to bake the overlays into the uploaded PNG. For video stories the overlay list is persisted as `overlays: [...]` JSON on the Firestore doc and re-rendered live by the viewer.

## Firestore collections touched
- `stories/{storyId}` — story doc.
- `stories/{storyId}/viewers/{uid}` — view receipt.
- `stories/{storyId}/likes/{uid}` — like.
- `stories/{storyId}/comments` — comment subcollection (`StoryService.addStoryComment` etc.).
- `users/{uid}` — to denormalize username + avatar onto the story doc on create.
- `chats/{chatId}/messages` — DM replies (via `ChatService.sendMessage`).

## Services used
- [story_service.dart](../../lib/src/services/story_service.dart) — `createStory`, `hasViewed`, `markViewed`, `toggleLike`, `streamLikers`, `streamViewers`, `addStoryComment`, etc.
- [own_story_seen_service.dart](../../lib/src/services/own_story_seen_service.dart) — local "I've seen my own stories' viewers" tracking.
- [storage_service.dart](../../lib/src/services/storage_service.dart) — `uploadStoryImage`, `uploadStoryVideo`.
- [chat_service.dart](../../lib/src/services/chat_service.dart) — used by reply-to-story DM.
- `notification_service.dart` — story-like / story-reply notifications.
- `camera`, `image_picker`, `photo_manager`, `flutter_native_video_trimmer`, `video_player`, `share_plus`.

## Non-obvious business rules
- Story duration is **24 h** (`expiresAt = createdAt + 24h`). Expiry is computed at create time, no server-side cleanup hook is invoked from these screens (handled elsewhere / by query filter).
- Video trim is metadata-only unless the trimmed window would still exceed 30 MB.
- For text stories, `imageUrl` is intentionally left empty — the viewer routes on `story.isText`.
- The owner-bubble is always first in `StoriesList`. If the owner has no active story, tapping it opens `AddToStoryScreen` rather than entering the viewer.
- Reply-to-story: cannot reply to your own story (author / sender match short-circuits).
- The progress bar pauses both for long-press AND when the reply input has focus or text — typing must not race past the story.
- Liking and quick-reacting are unified: the heart fires both a like AND sends a heart DM; other emojis only send a DM.
- `Story.isText` requires textContent non-empty AND `imageUrl` empty AND not video AND not shared-post — strict so a video story with overlays doesn't accidentally render as text.
- `StoriesList` height is fixed at 110 px and the section is only mounted when `cfg.storiesEnabled` is true.

## Localization
- `story_viewer_screen.dart`: ~34 `context.t.*` calls.
- composers + section: 1-11 per file.

## Related files
- `lib/src/features/widgets/story_section.dart`
- `lib/src/features/widgets/story_item.dart`
- `lib/src/features/widgets/story_text_overlay.dart`
- `lib/src/features/screens/story_viewer_screen.dart`
- `lib/src/features/screens/story_preview_screen.dart`
- `lib/src/features/screens/text_story_composer_screen.dart`
- `lib/src/features/screens/camera_story_screen.dart`
- `lib/src/features/screens/add_to_story_screen.dart`
- `lib/src/features/screens/video_story_preview_screen.dart`
- `lib/src/services/story_service.dart`
- `lib/src/services/own_story_seen_service.dart`
- `lib/src/services/storage_service.dart`
- `lib/src/providers/story_providers.dart`
- `lib/src/features/model/story_comment_model.dart`
