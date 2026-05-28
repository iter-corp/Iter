# Comments and Discuss (Q&A)

## What this feature does
Two related but distinct surfaces: regular post comments (`CommentScreen` — modal bottom sheet on any feed/travel post) and the Discuss / Q&A thread view (`QaThreadScreen` — a full-screen route opened when the post is a Q&A topic, i.e. `discussKind != null` or "discuss this post" promoted a feed post). Both use the **same** `posts/{postId}/comments` subcollection (and the same `Comment` model) — the difference is only in presentation: `QaThreadScreen` renders the post as a "question card", treats top-level comments as "answers", supports a helpful/unhelpful reaction bar, and lets the asker pin a specific answer. A comment can be a top-level entry or a reply (`parentCommentId` + `replyToUsername`). Profanity moderation is **sender-only**: a flagged comment lands in a per-user `privateComments` subcollection instead of the public `comments` subcollection so only the author sees it, with a "Visible only to you" red label.

## Key screens / widgets
- [comment_screen.dart](../../lib/src/features/screens/comment_screen.dart) — modal bottom sheet. Header counts only `c => !c.senderOnly`. Reply chip + input row. Top-level + replies grouped via `repliesByParent`. Supports `highlightCommentId` and `highlightAuthorUid` arrival from a notification tap.
- [qa_thread_screen.dart](../../lib/src/features/screens/qa_thread_screen.dart) — full-screen variant. `_QuestionCard` shows the question + optional `_EmbeddedPostCard` of the source post. `_AnswersHeader`, `_AnswerBlock`, `_AnswerReactionBar` (helpful/unhelpful). Supports `pinUid` (pin a user's answers) and `pinCommentId` (pin one answer).

## Threading model
- 1-level deep: replies set `parentCommentId` to a top-level comment id. A reply to a reply still uses the same top-level `parentCommentId` (see `_replyTo` setup: `parent.parentCommentId ?? parent.id`).
- `replyToUsername` is stored separately so the rendered text shows the `@username` prefix in purple even after deletion.
- `repliesByParent` map groups replies under their top-level parent in the UI.

## Regular comments vs Discuss / Q&A
- Both live under `posts/{postId}/comments`.
- `QaThreadScreen` renders only when `post.discussKind != null` or when the post became a discuss topic (see `discussPost` in `post_card.dart` and `PostService.createQaPostFromPost`).
- Notification fan-out branches on `posts.postType == 'qa'` (`CommentService.addComment`): `qa_answer` for top-level answers, `qa_reply` for replies; otherwise `comment` (top-level) or `reply`.
- The Q&A answer reaction bar uses `helpfulCount` / `unhelpfulCount` (stored on each `Comment` doc) rendered by `_AnswerReactionBar`.
- Sort: `streamComments` merges public + sender-only and sorts:
  1. Viewer's own first.
  2. Then by `likesCount desc`.
  3. Then by `createdAt desc`.
  4. Stable tie-break on `id`.

## Sender-only profanity moderation
- `CommentService.addComment` calls `ProfanityFilterService.findMatches(text)`.
- On match: write to `posts/{postId}/privateComments/{uid}/items/{commentId}` with `profanityFiltered: true` and `senderOnly: true`. **Public `commentsCount` is NOT incremented.** No notifications are fired. The author's UI shows their comment with the red "Visible only to you" label (`context.t.visibleOnlyToYou`), and the bubble text turns dark-red.
- `streamComments` merges the viewer's own `privateComments` items with the public `comments` subcollection, so the author sees their own filtered comment but no one else does.
- Edit rules (`CommentService.editComment`):
  - Editing a **sender-only** comment that becomes clean → moved to the public collection (copy + delete + increment `commentsCount`).
  - Editing a **public** comment so that the new text is dirty → throws `ProfanityEditRejected` and rolls back; the public copy stays visible. Rationale (verbatim from code): "editing a public comment into a flagged one would be a way to sneak content past readers who already saw the clean version."
- Sender-only comments cannot be liked (`onToggleLike` early-returns if `comment.senderOnly`).
- A "deleted user" UI fallback renders italic "deleted user" with no avatar when `liveAsync.hasValue && liveUser == null` — the comment text remains.

## Report flow
- Both `CommentScreen` (via `_ViewerMenu` on the host `PostCard`) and `QaThreadScreen` (`_QuestionCard._reportQuestion`) use the **same 7 reasons**: `Spam or scam`, `Harassment or bullying`, `Hate speech`, `Violence or threats`, `Nudity or sexual content`, `Misinformation`, `Something else`. Each label is localized via `context.t.reportReasonLabel(reason)`.
- Reporting a question writes to `discussReports/{reportId}` via `PostService.reportQaPost`.
- Reporting a regular post writes to `postReports/{reportId}` via `PostService.reportPost`.
- Authors cannot report their own content (`canReport = currentUid != null && currentUid != post.authorUid`).

## Comment translation
- `_CommentTranslateSheet` opens from each comment's overflow menu. Calls `TranslateService.translateText(text, targetLang)`.
- Lets the user pick a target language and re-translates on selection (`_selectLang` → `_translate`). The "Copy" button copies the translated text to clipboard.

## Highlight + scroll on notification arrival
- `CommentScreen` accepts `highlightCommentId` and `highlightAuthorUid`.
- If the highlighted comment is a reply, its parent is force-expanded so the row is built.
- A short post-frame scroll runs to ensure the reply row is actually mounted before scrolling.
- The highlighted bubble gets an elevated `AppGlassCard` with a purple glow `BoxShadow`.

## Firestore collections touched
- `posts/{postId}/comments` — public comments / answers.
- `posts/{postId}/privateComments/{uid}/items` — sender-only filtered comments.
- `posts/{postId}/comments/{commentId}/likes` — per-comment likes.
- `posts/{postId}/comments/{commentId}/reactions` — helpful/unhelpful reaction docs (Q&A).
- `posts/{postId}` — `commentsCount` increment (public only).
- `postReports/{reportId}` and `discussReports/{reportId}` — reports.
- `notifications/{uid}/items` — fanned out via `NotificationService.upsertNotification`.

## Services used
- [comment_service.dart](../../lib/src/services/comment_service.dart) — `streamComments`, `addComment`, `editComment`, `deleteComment`, `toggleLikeComment`, `streamCommentLikesCount`, `streamIsCommentLiked`, `streamCommentsCount`, `_backfillMissingLikesCount`.
- [profanity_filter_service.dart](../../lib/src/services/profanity_filter_service.dart) — backed by the admin-managed blacklist.
- [translate_service.dart](../../lib/src/services/translate_service.dart) — used by `_CommentTranslateSheet`.
- [notification_service.dart](../../lib/src/services/notification_service.dart) — `upsertNotification` for `comment`, `reply`, `qa_answer`, `qa_reply`.

## Non-obvious business rules
- `commentsCount` on the post is incremented only for public comments — never for sender-only ones — so the badge stays accurate to what other users actually see.
- `_backfillMissingLikesCount` is a one-time migration that fills `likesCount` on older comment docs by counting `likes` subcollection size; failures are silently swallowed.
- Top-level comments on a non-QA post notify the post's author (this branch was previously missing per the in-code comment; debugPrint logs trace the fan-out).
- `_ReplyTarget.parentCommentId` is normalized to the top-level parent so deep replies are still anchored under the original top-level comment.
- Q&A threads call out a question by parsing the caption: the first line is treated as the title, the rest as body (`title = lines.first; body = lines.sublist(1).join('\n')`).
- The fallback "Untitled question" string is shown when caption is empty.
- `discussKind` of `'question'` is used as a hard marker; if absent, the screen falls back to "does title contain a '?'".

## Localization
- `comment_screen.dart`: ~13 `context.t.*` calls.
- `qa_thread_screen.dart`: ~42 `context.t.*` calls.

## Related files
- `lib/src/features/screens/comment_screen.dart`
- `lib/src/features/screens/qa_thread_screen.dart`
- `lib/src/services/comment_service.dart`
- `lib/src/services/profanity_filter_service.dart`
- `lib/src/services/translate_service.dart`
- `lib/src/services/notification_service.dart`
- `lib/src/providers/comment_providers.dart`
- `lib/src/providers/reaction_providers.dart`
- `lib/src/services/reaction_service.dart`
