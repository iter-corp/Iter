# Chat and Messaging

## What this feature does
Three thread types live under almost the same shape: 1:1 direct chats (`chats/{chatId}`, deterministic id `${sortedUidA}_${sortedUidB}`), group chats (`chats/{chatId}` with multiple participants + admin metadata), and event chats (`eventChats/{eventId}` — auto-created when an event is created, all event registrants are participants). All three render through `ChatScreen` (DM + group) or `EventChatScreen`. Messages support text, image, video, voice (with on-device live transcript), sticker (bundled assets + user-uploaded packs), file attachment, location pin, shared post, shared story, and reply-to-another-message. Reactions are stored as a per-message subcollection. The Messages tab (`MessageScreen`) splits into **All** and **Requests** — a chat moves out of Requests once both participants follow each other (mutual follow) or the receiver explicitly accepts. **End-to-end encryption was removed**; legacy `enc` envelopes are detected and rendered as a `🔒 Couldn't decrypt on this device` placeholder.

## Key screens / widgets
- [chat_screen.dart](../../lib/src/features/screens/chat_screen.dart) — 5 000-line full chat surface. 1:1 and group both. Handles compose row, voice record (`record` pkg + `speech_to_text` for transcript), image/video/file pickers, location share, sticker sheet, reply target, reaction long-press, retry queue for failed uploads, auto-translate-incoming toggle (persisted per chat in `SharedPreferences`).
- [message_screen.dart](../../lib/src/features/screens/message_screen.dart) — inbox. `MessageTabBar` (All / Requests), search, group-create FAB (`showCreateGroupSheet`).
- [event_chat_screen.dart](../../lib/src/features/screens/event_chat_screen.dart) — event-specific thread. Uses `eventChatServiceProvider` and `eventChatMessagesProvider`. `_EventMessageBubble`. Shows `_EventChatNotEncryptedNotice`. Polls are created via `parentPath: 'eventChats/$eventId/messages'`.
- [group_settings_screen.dart](../../lib/src/features/screens/group_settings_screen.dart) — admin/non-admin views. Permission toggles (`restrictMessaging`, `adminOnly`, `mediaShare`), member list, leave / remove.
- [event_group_settings_screen.dart](../../lib/src/features/screens/event_group_settings_screen.dart) — analogous for event chats.
- [message_widget.dart](../../lib/src/features/widgets/message_widget.dart) — `MessageTabBar`, `MessageTile`, `_UnreadCountBadge`.
- [sticker_picker_sheet.dart](../../lib/src/features/widgets/sticker_picker_sheet.dart) — tab strip of sticker categories (bundled `sticker_data.dart` + user-uploaded packs via `customStickerPacksProvider`).
- [create_group_sheet.dart](../../lib/src/features/widgets/create_group_sheet.dart) — modal sheet to create a group from the user's following list.
- [message_reactions_bar.dart](../../lib/src/features/widgets/message_reactions_bar.dart) — reaction emoji bar (long-press on a bubble).

## Message types (all in one doc shape, populated fields discriminate)
- **Text** — `text`.
- **Image** — `imageUrl`.
- **Video** — `videoUrl`.
- **Voice** — `voiceUrl` + `voiceDurationMs` + optional `voiceTranscript` (on-device speech-to-text captured live while recording).
- **Sticker** — `stickerUrl` (asset: path for bundled, network URL for custom) + `stickerPackId`.
- **File** — `fileUrl` + `fileName` + `fileMimeType` + `fileSizeBytes`.
- **Shared post** — `sharedPostId`.
- **Shared story** — `storyId` + `storyImageUrl`. Used by reply-to-story flow.
- **Location pin** — `location: {lat, lng}` + `locationLabel`. Renders a mini map preview + Directions action.
- **Reply** — any of the above plus `replyToId`, `replyToText`, `replyToSenderUid`.

## Reply target + reaction
- `ChatScreen._replyTarget` holds the pending reply; the input bar shows a stripe with the original snippet, send strips it onto the new message.
- Tapping a reply scrolls to the original (`_replyFlash` highlights for ~1 s).
- Long-press a bubble → `message_reactions_bar.dart` → writes to a per-message `reactions` subcollection via `ReactionService`.

## Profanity moderation
- `ChatService.sendMessage` runs text through `ProfanityFilterService.findMatches`.
- On match: the wire-visible `text` is **empty**, but `senderOnlyText` carries the original. Bubble reads `senderOnlyText` first; only the sender sees the original, the receiver sees the message as filtered (per `_previewTextForMessage` returning `"Message visible only to sender"`).
- The `profanityFiltered` flag (or `moderation.type == 'profanity'`) is set on the doc.

## Encryption status (verbatim from code)
- "Legacy ciphertext from before the encryption stack was removed — can't recover the original." Docs with an `enc` map are rendered as **Message unavailable**.
- `ChatMessage.encryptedUnreadable` is set when a doc has an `enc` envelope that this device couldn't decrypt; bubble renders a 🔒 placeholder.
- New messages are sent **in plaintext** at the Firestore-doc layer (Firestore transport TLS still applies). `EventChatScreen` displays a `_EventChatNotEncryptedNotice` banner.

## Message cache
- [message_cache.dart](../../lib/src/services/message_cache.dart) (~186 lines). Persists per-chat snapshots to disk as JSON via `ChatMessage.toCacheJson` / `fromCacheJson`. `streamMessages` emits the cached snapshot synchronously for the first frame, then replaces entries as live docs arrive.
- The cache resolves the cold-start blank-screen flash and lets reply scrolls work before the network round-trip completes.

## Group permissions (admin-controlled in `GroupSettingsScreen`)
- `restrictMessaging` — only admins can send messages.
- `adminOnly` — composite (only admins post + react).
- `mediaShare` — when false, image/video/file sends are blocked with a localized snackbar (`mediaSharingDisabledGroup`).
- Member roles: owner (creator), admins, regular members. Owner has a special "creator" badge. Leaving the group calls `ChatService.leaveOrRemoveGroupMember`.

## Mutual-follow request gate
- `ChatService.openChat` computes `_isMutualFollow(a, b)`. If true → both uids are pre-`acceptedBy` → chat appears in both inboxes' "All" tab. Otherwise only the initiator is `acceptedBy` → the receiver sees it in "Requests" until they accept.

## Conversation summary + unread
- `_previewTextForMessage` renders the last-message line. Special-cases sticker / shared post / voice / video / file / image / location / shared story / profanity-filtered / encrypted-legacy.
- `_latestVisibleMessageDoc` walks the most recent 50 messages and picks the newest one **visible to this viewer** — supports per-user delete (`deletedForUids`) and `visibleToUids` audience scoping.
- `_refreshChatSummary` writes back `lastMessage` / `lastMessageSenderUid` / `lastTime` on the chat doc; the inbox renders from those denormalized fields.

## Presence + typing
- [presence_service.dart](../../lib/src/services/presence_service.dart) — Realtime Database path `presence/{uid}`. Sets `online:true` + `onDisconnect()` writes `online:false`. `statusText`: "Online" / "last seen just now / Nm ago / Nh ago / Nd ago".
- [typing_service.dart](../../lib/src/services/typing_service.dart) — RTDB path `typing/{chatId}/{uid}`. Same `onDisconnect()` cleanup. `listenTyping` exposed in `ChatScreen` for the "typing…" indicator.

## Stickers
- Bundled stickers in [sticker_data.dart](../../lib/src/services/sticker_data.dart) (asset paths).
- User-uploaded sticker packs through [sticker_service.dart](../../lib/src/services/sticker_service.dart) and `customStickerPacksProvider`.
- Pack tabs at the bottom of `StickerPickerSheet`.

## Voice messages
- `record` pkg captures audio.
- `speech_to_text` runs live during recording and stores the result as `voiceTranscript` so the receiver can read or translate without a server-side transcription step.
- Voice file is uploaded via `StorageService`.

## Auto-translate incoming (per chat)
- Toggleable from chat menu; persisted to `SharedPreferences` keyed by chat id.
- When enabled, incoming bubbles call `TranslateService.translateText` into the user's preferred language (`preferredLanguageProvider`).

## Firestore collections touched
- `chats/{chatId}` (denormalized `participants`, `userData`, `lastMessage`, `lastTime`, `unreadCounters`, `acceptedBy`, group fields `groupName`, `groupIcon`, `admins`, `createdBy`, `restrictMessaging`, `adminOnly`, `mediaShare`, `visibleToUids`).
- `chats/{chatId}/messages/{messageId}` — `ChatMessage`. Subcollection `reactions/{uid}` for reactions.
- `eventChats/{eventId}` + `eventChats/{eventId}/messages` — event variant.
- `users/{uid}` (denormalization on chat creation).
- RTDB: `presence/{uid}`, `typing/{chatId}/{uid}`.
- `polls` — via `showCreatePollSheet(parentPath)`.

## Services used
- [chat_service.dart](../../lib/src/services/chat_service.dart) — `openChat`, `sendMessage`, `streamMessages`, `streamConversations`, `markSeen`, `deleteForMe`, `deleteForEveryone`, `leaveOrRemoveGroupMember`, `createGroup`.
- [event_chat_service.dart](../../lib/src/services/event_chat_service.dart) — event-chat equivalents.
- [message_cache.dart](../../lib/src/services/message_cache.dart) — on-disk snapshot cache.
- [presence_service.dart](../../lib/src/services/presence_service.dart) + [typing_service.dart](../../lib/src/services/typing_service.dart).
- [reaction_service.dart](../../lib/src/services/reaction_service.dart).
- [sticker_service.dart](../../lib/src/services/sticker_service.dart), [sticker_data.dart](../../lib/src/services/sticker_data.dart).
- [storage_service.dart](../../lib/src/services/storage_service.dart) — media uploads.
- [translate_service.dart](../../lib/src/services/translate_service.dart) — bubble translation.
- [block_service.dart](../../lib/src/services/block_service.dart) — block check gates the compose row.
- `record`, `audioplayers`, `speech_to_text`, `file_picker`, `image_picker`, `video_player`, `geolocator`, `geocoding`.

## Non-obvious business rules
- Sender-only profanity moderation: wire text is empty, sender reads from `senderOnlyText`. Receiver preview reads `"Message visible only to sender"`.
- Per-user delete: `deletedForUids` (single) and `deletedForEveryoneAt` (everyone). The viewer filter applies both before rendering.
- Visibility scoping: `visibleToUids` (empty = visible to all) allows targeted messages within a group — used by admin actions.
- Mutual follow → automatic accept; otherwise the chat starts in Requests.
- Message preview de-emojify rules are localized strings; the `📍` for location is hardcoded into the preview line.
- Event chat has no encryption; explicit `_EventChatNotEncryptedNotice` informs the user.
- Polls' `parentPath` is the chat or eventChat's `messages` collection — polls are stored as messages there.

## Localization
- `chat_screen.dart`: ~119 `context.t.*` calls.
- `message_screen.dart`: ~42.
- `event_chat_screen.dart`: ~9.
- `group_settings_screen.dart`: ~28.
- `event_group_settings_screen.dart`: ~37.

## Related files
- `lib/src/features/screens/chat_screen.dart`
- `lib/src/features/screens/message_screen.dart`
- `lib/src/features/screens/event_chat_screen.dart`
- `lib/src/features/screens/group_settings_screen.dart`
- `lib/src/features/screens/event_group_settings_screen.dart`
- `lib/src/features/widgets/message_widget.dart`
- `lib/src/features/widgets/message_reactions_bar.dart`
- `lib/src/features/widgets/sticker_picker_sheet.dart`
- `lib/src/features/widgets/create_group_sheet.dart`
- `lib/src/features/widgets/poll_widgets.dart`
- `lib/src/services/chat_service.dart`
- `lib/src/services/event_chat_service.dart`
- `lib/src/services/message_cache.dart`
- `lib/src/services/presence_service.dart`
- `lib/src/services/typing_service.dart`
- `lib/src/services/reaction_service.dart`
- `lib/src/services/sticker_service.dart`
- `lib/src/services/sticker_data.dart`
- `lib/src/services/storage_service.dart`
- `lib/src/services/block_service.dart`
- `lib/src/providers/chat_providers.dart`
- `lib/src/providers/event_chat_providers.dart`
- `lib/src/providers/reaction_providers.dart`
- `lib/src/providers/preferred_language_provider.dart`
