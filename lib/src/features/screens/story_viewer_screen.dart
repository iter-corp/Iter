import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_strings.dart';
import '../../navigation/user_profile_nav.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../providers/post_providers.dart';
import '../../providers/story_providers.dart';
import '../../services/own_story_seen_service.dart';
import '../../services/story_service.dart';
import '../../theme/app_theme.dart';
import '../model/post_model.dart';
import '../widgets/event_share.dart';
import '../widgets/story_text_overlay.dart';
import 'post_detail_screen.dart';
import 'text_story_composer_screen.dart';

const Duration _kStoryDuration = Duration(seconds: 5);

Future<T?> openStoryViewer<T>(
  BuildContext context,
  List<List<Story>> allGroups,
  int initialGroupIndex,
) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 450),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => StoryViewerScreen(
        allGroups: allGroups,
        initialGroupIndex: initialGroupIndex,
      ),
      transitionsBuilder: (_, animation, __, child) {
        final scale = Tween<double>(begin: 0.55, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );
        final fade = CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
          reverseCurve: const Interval(0.2, 1.0, curve: Curves.easeIn),
        );
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
    ),
  );
}

class StoryViewerScreen extends ConsumerStatefulWidget {
  final List<List<Story>> allGroups;
  final int initialGroupIndex;
  const StoryViewerScreen({
    super.key,
    required this.allGroups,
    required this.initialGroupIndex,
  });

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  int _groupIndex = 0;
  int _index = 0;
  late final List<List<Story>> _allGroups;
  final StoryService _storyService = StoryService();
  late final AnimationController _progress;
  String? _loadingForStoryId;

  /// Bumped each time the user navigates between stories so any in-
  /// flight video-ready signal from the previous story can be ignored.
  int _navToken = 0;

  /// True once we've started closing the viewer, so the close (a
  /// `Navigator.pop`) can never run twice. A video reaching its end can
  /// fire the completion callback from two sources in the same frame
  /// (the controller listener and the position timer); without this
  /// guard the last story would pop the viewer AND then pop the screen
  /// beneath it, leaving a black screen.
  bool _closing = false;

  /// Resume the progress bar after a pause (long-press release, modal
  /// dismiss, etc). Image / text stories run on the AnimationController
  /// so we just `forward()`. Video stories are driven by the player's
  /// position timer — we mustn't call `forward()` there because the
  /// controller would race the video. Instead the timer will continue
  /// emitting position updates once the player resumes.
  void _resumeProgress() {
    final story = _currentStory;
    if (story == null) return;
    if (story.isVideo) {
      // Nothing to do — the video player's position timer drives the
      // bar. If the player itself was paused via [_longPressPaused],
      // resuming it elsewhere will restart playback and the timer
      // will tick the bar forward again.
      return;
    }
    _progress.forward();
  }

  /// Tracks the group index that's currently on screen so the
  /// transition builder can distinguish "next story (same author)" from
  /// "next author" and pick a different animation for each. Updated
  /// inside `_buildStoryBody` right before the new story renders.
  int _lastGroupIndexForAnim = -1;

  /// True while the user is long-pressing the story — pauses the
  /// progress timer AND the video player. Read by [_VideoStoryPlayer]
  /// via the notifier below.
  final ValueNotifier<bool> _longPressPaused = ValueNotifier(false);

  // Like and comment state
  bool _isLiking = false;
  final TextEditingController _commentController = TextEditingController();
  bool _sendingComment = false;
  final FocusNode _commentFocusNode = FocusNode();

  List<Story> get _stories =>
      (_groupIndex >= 0 && _groupIndex < _allGroups.length)
          ? _allGroups[_groupIndex]
          : const <Story>[];

  /// Returns the story currently being shown, or null if the indexes are
  /// out of bounds (e.g. after the last story in the last group is
  /// deleted while the viewer is open). Callers must handle null and
  /// pop or skip — never assume the index is valid.
  Story? get _currentStory {
    final group = _stories;
    if (group.isEmpty) return null;
    if (_index < 0 || _index >= group.length) return null;
    return group[_index];
  }

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    // Filter out empty groups defensively — one malformed group used to
    // throw RangeError("No element") from _stories[_index].
    _allGroups = widget.allGroups
        .map((g) => List<Story>.of(g))
        .where((g) => g.isNotEmpty)
        .toList();
    _groupIndex = widget.initialGroupIndex.clamp(
      0,
      _allGroups.isEmpty ? 0 : _allGroups.length - 1,
    );
    _progress = AnimationController(
      vsync: this,
      duration: _kStoryDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _next();
        }
      });
    _commentFocusNode.addListener(_onReplyFocusChange);
    // Text changes also gate auto-advance: if the user has typed
    // anything we treat them as still composing even if focus briefly
    // bounces (autocomplete strips, picker dialogs etc).
    _commentController.addListener(_onReplyTextChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_allGroups.isEmpty) {
        Navigator.of(context).maybePop();
        return;
      }
      _startCurrent();
    });
  }

  /// Pauses the auto-advance progress when the user focuses the reply
  /// input (typing a reply) and resumes when they unfocus AND the input
  /// is empty. Without the "and empty" guard the story used to advance
  /// the instant focus bounced (autocomplete strips, suggestion picker)
  /// even though the user was still mid-message.
  void _onReplyFocusChange() => _updateReplyPauseState();
  void _onReplyTextChange() => _updateReplyPauseState();

  void _updateReplyPauseState() {
    if (!mounted) return;
    final composing = _commentFocusNode.hasFocus ||
        _commentController.text.isNotEmpty;
    if (composing) {
      // Reset progress to 0 so the user gets the full 5s window once
      // they're done typing, rather than the story snapping to the next
      // because there were only ~200ms left when they started.
      _progress.stop();
      _progress.value = 0;
    } else {
      _resumeProgress();
    }
  }

  @override
  void dispose() {
    _commentFocusNode.removeListener(_onReplyFocusChange);
    _commentController.removeListener(_onReplyTextChange);
    _longPressPaused.dispose();
    _progress.dispose();
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _toggleLike({bool silent = false}) async {
    final story = _currentStory;
    if (story == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.storySignInToLike)),
        );
      }
      return;
    }

    if (_isLiking) return;

    setState(() => _isLiking = true);
    await HapticFeedback.lightImpact();

    try {
      await _storyService.toggleLike(story.id);
    } catch (e) {
      // Story like is best-effort. When called via _quickReact (silent=true)
      // the user already sees "Sent ❤️" feedback; the most common failure
      // here is a Firestore rules race on the parent story doc's likesCount
      // update. Swallow silently so the viewer doesn't flash an alarming
      // permission-denied banner alongside a successful DM.
      debugPrint('[story-like] toggleLike failed: $e');
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.storyFailedToggleLike(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLiking = false);
    }
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _sendingComment = true);
    final ok = await _replyToStoryAsDM(text);
    if (!mounted) return;
    setState(() => _sendingComment = false);
    if (ok) {
      _commentController.clear();
      _commentFocusNode.unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.storyReplySent)),
      );
    }
  }

  /// Opens (or finds) the 1:1 chat with the current story's author and
  /// sends [text] there with a reference back to the story (storyId +
  /// thumbnail). Returns true on success. Used by both the reply input
  /// and the quick-reactions row. The story author can't reply to their
  /// own story — we no-op in that case so we never DM ourselves.
  Future<bool> _replyToStoryAsDM(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      debugPrint('[story-reply] empty text, skipping');
      return false;
    }
    final story = _currentStory;
    if (story == null) return false;
    final me = _currentUid;
    debugPrint('[story-reply] me=$me author=${story.authorUid} '
        'storyId=${story.id} text="${trimmed.length > 30 ? "${trimmed.substring(0, 30)}…" : trimmed}"');
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.storySignInToReply)),
      );
      return false;
    }
    if (story.authorUid == me) {
      debugPrint('[story-reply] author == me, no DM');
      return false;
    }

    try {
      final chatService = ref.read(chatServiceProvider);
      debugPrint('[story-reply] openChat…');
      final chatId = await chatService.openChat(
        currentUid: me,
        otherUid: story.authorUid,
      );
      debugPrint('[story-reply] openChat OK chatId=$chatId, sending…');
      await chatService.sendMessage(
        chatId: chatId,
        senderUid: me,
        receiverUid: story.authorUid,
        text: trimmed,
        storyId: story.id,
        storyImageUrl: story.imageUrl,
      );
      debugPrint('[story-reply] sendMessage OK');
      return true;
    } catch (e, st) {
      debugPrint('[story-reply] FAILED: $e\n$st');
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.storyFailedSendReply(e))),
      );
      return false;
    }
  }

  Future<void> _startCurrent() async {
    final story = _currentStory;
    if (story == null) {
      // Nothing to play — close the viewer rather than spinning
      // forever on an invalid index.
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    _progress.stop();
    _progress.value = 0;
    _loadingForStoryId = story.id;

    // Record the view immediately — don't gate it behind image preload so
    // fast taps through stories are still counted. `recordView` early-
    // returns for the author themselves, so we never count the user as
    // a viewer of their own story.
    _storyService
        .recordView(story.id, authorUid: story.authorUid)
        .catchError((Object e, StackTrace _) {
      debugPrint('recordView failed for ${story.id}: $e');
    });

    if (_currentUid != null && story.authorUid != _currentUid) {
      ref.read(locallyViewedStoryIdsProvider.notifier).update(
            (seen) => {...seen, story.id},
          );
    }

    // If this is one of the user's OWN stories, mark it locally as seen
    // so the home rail can dim the ring on next paint. This is a
    // device-local flag (SharedPreferences) — it intentionally does NOT
    // get written to Firestore, so the author never appears in their
    // own viewers list.
    if (_currentUid != null && story.authorUid == _currentUid) {
      // Notifier-based markSeen updates the in-memory set so the home
      // story rail's `ownStoriesAllSeenProvider` watcher re-evaluates
      // synchronously and drops the purple ring on the next paint.
      // We also snapshot the CURRENT viewer count so the ring stays
      // dim until a NEW viewer arrives — then the count exceeds this
      // snapshot and the ring lights up again.
      final currentCount =
          ref.read(storyViewersCountProvider(story.id)).asData?.value ?? 0;
      ref
          .read(ownStorySeenProvider.notifier)
          .markSeen(story.id, currentViewerCount: currentCount)
          .catchError((Object e) {
        debugPrint('markSeen (own) failed for ${story.id}: $e');
      });
    }

    // Per-story nav token: if the user advances past this story before
    // its media finishes loading, the post-load callback below sees a
    // stale token and skips starting the timer.
    _navToken++;
    final token = _navToken;

    if (story.isVideo) {
      // Wait until the video has loaded its first frame and started
      // playing. The progress bar is then driven directly by the
      // player's playback clock via `onPositionUpdate` — no
      // independent animation timer for video stories, so the bar
      // can't drift or race the video.
      await _waitForVideoReady(token);
      if (!mounted ||
          _loadingForStoryId != story.id ||
          token != _navToken) {
        return;
      }
      _progress.stop();
      _progress.value = 0;
      // Don't `forward()` — the video player will write into
      // `_progress.value` on every tick.
      return;
    }
    try {
      await precacheImage(
        CachedNetworkImageProvider(story.imageUrl),
        context,
      );
    } catch (_) {
      // Fall through — still start the timer so the viewer never
      // locks up if precache fails.
    }
    if (!mounted ||
        _loadingForStoryId != story.id ||
        token != _navToken) {
      return;
    }
    // Images use the fixed 5s tick.
    _progress.duration = _kStoryDuration;
    _progress.forward(from: 0);
  }

  // Signaled by [_VideoStoryPlayer.onReady] once `initialize()` finishes
  // and the first frame is on screen. We keep ONE active completer at
  // a time, replaced each nav; `onReady` always resolves the current
  // one regardless of its token. Token mismatches still get caught
  // downstream by the navToken check in `_startCurrent`.
  Completer<Duration>? _videoReadyCompleter;

  Future<Duration> _waitForVideoReady(int token) {
    // If a prior wait is still pending (user advanced past it before
    // its video loaded), unblock it so its downstream isn't leaked.
    final prior = _videoReadyCompleter;
    if (prior != null && !prior.isCompleted) {
      prior.complete(Duration.zero);
    }
    final c = Completer<Duration>();
    _videoReadyCompleter = c;
    return c.future;
  }

  void _onVideoReady(int token, Duration effective) {
    final c = _videoReadyCompleter;
    if (c != null && !c.isCompleted) {
      _videoReadyCompleter = null;
      c.complete(effective);
    }
  }

  void _next() {
    // Re-entry guard: a video's completion can be observed by both the
    // controller listener and the position timer in the same frame, so
    // _next() can be invoked twice back-to-back. Ignore the second call
    // once we're already tearing the viewer down.
    if (_closing) return;
    if (_index < _stories.length - 1) {
      setState(() => _index++);
      _startCurrent();
    } else {
      _nextGroup();
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
      _startCurrent();
    } else {
      _prevGroup();
    }
  }

  /// Single close path for the viewer, guarded against the double-pop that
  /// would otherwise dismiss the screen underneath. Used by the explicit
  /// close button and the swipe-down gesture so the user can always leave —
  /// including while a story's media is still loading.
  void _close() {
    if (_closing) return;
    _closing = true;
    if (mounted) Navigator.pop(context);
  }

  void _nextGroup() {
    if (_groupIndex < _allGroups.length - 1) {
      setState(() {
        _groupIndex++;
        _index = 0;
      });
      _startCurrent();
    } else {
      // Last story of the last group finished — close the viewer.
      // Guard against a double pop (see [_closing]); popping twice would
      // dismiss the screen underneath and leave a black screen.
      if (_closing) return;
      _closing = true;
      if (mounted) Navigator.pop(context);
    }
  }

  void _prevGroup() {
    if (_groupIndex > 0) {
      setState(() {
        _groupIndex--;
        _index = 0;
      });
      _startCurrent();
    } else {
      // Already on the very first story — tapping "previous" can't go back
      // further, so restart the current story (standard story behavior)
      // instead of leaving the progress bar frozen.
      _startCurrent();
    }
  }

  Future<void> _openAuthorProfile(String uid) async {
    _progress.stop();
    await openUserProfile(context, uid: uid);
    if (mounted) _resumeProgress();
  }

  Future<void> _showViewersSheet(String storyId) async {
    _progress.stop();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ViewersSheet(
        storyId: storyId,
        service: _storyService,
      ),
    );
    if (mounted) _resumeProgress();
  }

  Future<void> _showLikersSheet(String storyId) async {
    _progress.stop();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LikersSheet(
        storyId: storyId,
        service: _storyService,
      ),
    );
    if (mounted) _resumeProgress();
  }

  /// Opens a "Share story" sheet with three options:
  ///   • Add to my story — re-shares the same content as a new 24h story.
  ///   • Share via apps — opens the OS share sheet with the story image URL.
  ///   • A list of recent chats so the user can DM the story directly.
  /// Pauses the progress timer while the sheet is open and resumes on close.
  Future<void> _openShareSheet(Story story) async {
    _progress.stop();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StoryShareSheet(
        story: story,
        onAddToMyStory: () async {
          Navigator.pop(context);
          await _addStoryToMyStory(story);
        },
        onShareExternally: () async {
          Navigator.pop(context);
          await _shareStoryExternally(story);
        },
        onSendToChat: (chatId, otherUid, title) async {
          Navigator.pop(context);
          await _sendStoryToChat(story, chatId, otherUid, title);
        },
      ),
    );
    if (mounted) _resumeProgress();
  }

  Future<void> _addStoryToMyStory(Story story) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = context.t;
    try {
      // Carry every field that defines what the story looks like —
      // otherwise re-sharing a text or video story would produce an
      // empty image-story (black screen).
      await _storyService.createStory(
        imageUrl: story.imageUrl,
        sharedPostId: story.sharedPostId,
        videoUrl: story.videoUrl,
        textContent: story.textContent,
        backgroundColor: story.backgroundColor,
        textColor: story.textColor,
        textBorderStyle: story.textBorderStyle,
      );
      messenger.showSnackBar(
        SnackBar(content: Text(strings.postCardAddedToStory)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.postCardStoryFailed(e))),
      );
    }
  }

  Future<void> _shareStoryExternally(Story story) async {
    final url = story.imageUrl.trim();
    if (url.isEmpty) return;
    final box = context.findRenderObject() as RenderBox?;
    await Share.share(
      url,
      sharePositionOrigin:
          box != null ? box.localToGlobal(Offset.zero) & box.size : null,
    );
  }

  Future<void> _sendStoryToChat(
      Story story, String chatId, String otherUid, String recipientTitle) async {
    final me = _currentUid;
    if (me == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final strings = context.t;
    try {
      await ref.read(chatServiceProvider).sendMessage(
            chatId: chatId,
            senderUid: me,
            receiverUid: otherUid,
            text: '',
            // Forward the story as an image (or as a shared-post bubble
            // when the story itself shares a post).
            imageUrl: story.sharedPostId == null || story.sharedPostId!.isEmpty
                ? story.imageUrl
                : null,
            sharedPostId: story.sharedPostId,
            storyId: story.id,
            storyImageUrl: story.imageUrl,
          );
      // "Story sent to <name>" — not "Reply sent". The old copy was
      // misleading because the user isn't replying to anything yet.
      messenger.showSnackBar(
        SnackBar(content: Text(strings.storyShared(recipientTitle))),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.storyShareFailed)),
      );
    }
  }

  /// Picks the renderer for the current story based on which fields the
  /// doc has. Shared-post stories take priority (they show the original
  /// post as a card), then video, then text-only, then plain image.
  /// Any text overlays attached to the story (placed at compose time)
  /// are rendered on top in the same coordinate space used by the
  /// editor so what you saw while composing matches the published frame.
  Widget _buildStoryBody(Story story) {
    Widget base;
    if (story.sharedPostId != null && story.sharedPostId!.isNotEmpty) {
      base = _SharedPostStoryView(postId: story.sharedPostId!);
    } else if (story.isVideo) {
      final tokenAtBuild = _navToken;
      base = _VideoStoryPlayer(
        url: story.videoUrl!,
        trimStart: story.videoTrimStartMs == null
            ? null
            : Duration(milliseconds: story.videoTrimStartMs!),
        trimEnd: story.videoTrimEndMs == null
            ? null
            : Duration(milliseconds: story.videoTrimEndMs!),
        // Signal back when the first frame is ready so the viewer can
        // start the progress timer (sized to the actual video length)
        // instead of running it against a black loading screen.
        onReady: (effective) => _onVideoReady(tokenAtBuild, effective),
        // Pauses the underlying VideoPlayer while the user long-presses
        // the story (mirrors the progress-timer pause).
        pausedNotifier: _longPressPaused,
        // Drive the story progress bar off the video's actual playback
        // clock. Stops the AnimationController and writes its value
        // directly so the bar fills in lockstep with the visible frames.
        //
        // Gated on `tokenAtBuild == _navToken`: while the AnimatedSwitcher
        // cross-fades to the next story, the OUTGOING video player is still
        // mounted for ~280ms and its position timer keeps firing. Without
        // this guard a stale player would (a) write into the new story's
        // progress bar — freezing it — and (b) reach end-of-video and call
        // _next() again, skipping the story after it. The token goes stale
        // the moment we advance, so a non-current player's callbacks become
        // no-ops.
        onPositionUpdate: (frac) {
          if (!mounted || tokenAtBuild != _navToken) return;
          if (_progress.isAnimating) _progress.stop();
          _progress.value = frac;
        },
        // Advance when the video actually finishes. Driven by the
        // player's controller (real EOF / trim-end) rather than the
        // polled progress fraction, so it fires exactly once and the
        // video never replays into a black frame.
        onCompleted: () {
          if (!mounted || tokenAtBuild != _navToken) return;
          _next();
        },
        // Re-key per story so a new VideoPlayerController is created
        // whenever the user advances past the current story — otherwise
        // the next story would inherit playback state.
        key: ValueKey('story-video-${story.id}'),
      );
    } else if (story.isText) {
      base = _TextStoryBackground(
        text: story.textContent!,
        backgroundColor: Color(story.backgroundColor ?? 0xFFB05ECC),
        textColor: Color(story.textColor ?? 0xFFFFFFFF),
        borderStyle: (story.textBorderStyle ?? 'none'),
      );
    } else {
      base = SizedBox.expand(
        child: CachedNetworkImage(
          imageUrl: story.imageUrl,
          // Fill the screen (crop overflow) so portrait images have no space
          // at the edges — same as video stories.
          fit: BoxFit.cover,
          placeholder: (_, __) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          errorWidget: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image, color: Colors.white),
          ),
        ),
      );
    }

    final hasEvent =
        story.sharedEventId != null && story.sharedEventId!.isNotEmpty;

    if (story.overlays.isEmpty && !hasEvent) return base;

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvas = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            base,
            for (final overlay in story.overlays)
              StoryOverlayStatic(
                overlay: overlay,
                canvasSize: canvas,
              ),
            if (hasEvent)
              Positioned(
                left: 0,
                right: 0,
                bottom: 96,
                child: Center(
                  child: _ViewEventChip(
                    eventId: story.sharedEventId!,
                    title: story.sharedEventTitle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _deleteCurrentStory() async {
    final story = _currentStory;
    if (story == null) return;
    _progress.stop();
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.storyDeleteTitle),
        content: Text(context.t.storyDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t.delete),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) {
      _resumeProgress();
      return;
    }

    try {
      await _storyService.deleteStory(story.id);
      if (!mounted) return;

      setState(() {
        if (_groupIndex < _allGroups.length) {
          if (_index >= 0 && _index < _allGroups[_groupIndex].length) {
            _allGroups[_groupIndex].removeAt(_index);
          }
          // Drop the group entirely if it has no stories left so we
          // don't end up landing on an out-of-bounds index next.
          if (_allGroups[_groupIndex].isEmpty) {
            _allGroups.removeAt(_groupIndex);
            if (_groupIndex >= _allGroups.length) {
              _groupIndex = _allGroups.length - 1;
            }
            _index = 0;
          } else if (_index >= _allGroups[_groupIndex].length) {
            _index = _allGroups[_groupIndex].length - 1;
          }
        }
      });

      if (_allGroups.isEmpty || _stories.isEmpty) {
        Navigator.pop(context);
        return;
      }

      _startCurrent();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.storyDeleteFailed(e))),
      );
      _resumeProgress();
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = _currentStory;
    if (story == null) {
      // Fallback UI shown while we wait for initState's post-frame
      // callback to pop, or in the rare race where the viewer rebuilds
      // after the last story was deleted. Keeps the Scaffold valid so
      // Navigator.pop() can finish without painting against a torn
      // widget tree.
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    // After this frame commits (the one that ran the
    // AnimatedSwitcher's transitionBuilder against the OLD value of
    // `_lastGroupIndexForAnim`), advance the marker so the NEXT
    // transition compares against the now-current group.
    final groupForFrame = _groupIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _lastGroupIndexForAnim = groupForFrame;
    });
    final isOwnStory = story.authorUid == _currentUid;
    final width = MediaQuery.of(context).size.width;
    // Mirror tap/swipe direction in RTL so "tap on the leading edge =
    // previous, tap on the trailing edge = next". For LTR the leading
    // edge is the left; for RTL it's the right. Without this the user
    // tapped the same physical side regardless of locale, which feels
    // backwards in Arabic / Kurdish layouts.
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final userData = ref.watch(userByUidProvider(story.authorUid)).value;
    final avatarUrl = userData?['avatarUrl'] as String?;
    final username = userData?['username'] as String? ?? story.authorUsername;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        // Don't shrink the story canvas when the keyboard opens — that would
        // push the composer (positioned at bottom: 20) up toward the middle
        // of the now-shrunk body. Keep the Stack full-screen and lift only
        // the composer by viewInsets.bottom instead.
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: GestureDetector(
            onTapUp: (details) {
              // If the user is mid-reply (keyboard open OR text in
              // composer), the tap dismisses the keyboard instead of
              // advancing the story. Auto-advance is also paused via
              // `_updateReplyPauseState`, so the story sits still while
              // they keep typing.
              final keyboardVisible =
                  MediaQuery.of(context).viewInsets.bottom > 0;
              if (keyboardVisible ||
                  _commentFocusNode.hasFocus ||
                  _commentController.text.isNotEmpty) {
                _commentFocusNode.unfocus();
                return;
              }
              // Leading-edge third = previous, anywhere else = next.
              // In RTL the leading edge is the right side of the screen.
              final tappedLeading = isRtl
                  ? details.globalPosition.dx > width * 2 / 3
                  : details.globalPosition.dx < width / 3;
              if (tappedLeading) {
                _prev();
              } else {
                _next();
              }
            },
          onLongPressStart: (_) {
            _progress.stop();
            // Notify the video player (if any) so it pauses in sync.
            _longPressPaused.value = true;
          },
          onLongPressEnd: (_) {
            _longPressPaused.value = false;
            _resumeProgress();
          },
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) > 200) {
              _close();
            }
          },
          onHorizontalDragEnd: (details) {
            // Block group swipes while the keyboard is open / user is
            // composing a reply — same rule as tap-to-advance. Otherwise
            // a slight horizontal motion while reaching for the keyboard
            // could yank them off the story.
            final keyboardVisible =
                MediaQuery.of(context).viewInsets.bottom > 0;
            if (keyboardVisible ||
                _commentFocusNode.hasFocus ||
                _commentController.text.isNotEmpty) {
              return;
            }
            // Swipe semantics: leading-direction swipe = next group,
            // trailing-direction swipe = previous group. Velocity sign
            // is unaffected by Directionality, so flip the mapping in
            // RTL to match the user's mental model.
            final v = details.primaryVelocity ?? 0;
            final swipedToNext = isRtl ? v > 200 : v < -200;
            final swipedToPrev = isRtl ? v < -200 : v > 200;
            if (swipedToNext) {
              _nextGroup();
            } else if (swipedToPrev) {
              _prevGroup();
            }
          },
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  // AnimatedSwitcher fades the previous story out and
                  // the new one in whenever the keyed story changes.
                  // The slide direction depends on whether we're
                  // crossing into a new author (horizontal slide) or
                  // just advancing within the same author (subtle
                  // zoom/fade) — gives the user a felt difference
                  // between "next story" and "next person".
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) {
                      // Parse the group index out of the child's key and
                      // compare against the previous group (captured in
                      // `_lastGroupIndexForAnim`, which is updated on
                      // the next frame so this read still sees the old
                      // value during the transition). Author-to-author
                      // crossings get a horizontal slide; same-author
                      // advance gets a subtle fade+scale so the user
                      // feels which kind of jump happened.
                      int? childGroup;
                      final k = child.key;
                      if (k is ValueKey<String>) {
                        final match = RegExp(r'^group-(-?\d+)/')
                            .firstMatch(k.value);
                        if (match != null) {
                          childGroup = int.tryParse(match.group(1)!);
                        }
                      }
                      final isNewAuthor = childGroup != null &&
                          _lastGroupIndexForAnim != -1 &&
                          childGroup != _lastGroupIndexForAnim;
                      if (isNewAuthor) {
                        final slide = Tween<Offset>(
                          begin: const Offset(0.18, 0),
                          end: Offset.zero,
                        ).animate(anim);
                        return FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                              position: slide, child: child),
                        );
                      }
                      final scale = Tween<double>(begin: 1.04, end: 1.0)
                          .animate(anim);
                      return FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(scale: scale, child: child),
                      );
                    },
                    child: KeyedSubtree(
                      // The combined key changes both on story id and on
                      // group, so AnimatedSwitcher triggers a transition
                      // for either kind of advance.
                      key: ValueKey<String>(
                          'group-$_groupIndex/story-${story.id}'),
                      child: _buildStoryBody(story),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Row(
                    children: List.generate(_stories.length, (i) {
                      return Expanded(
                        child: Container(
                          height: 2.5,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: Stack(
                              children: [
                                Container(
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                                i < _index ? Container(color: Colors.white) : i == _index ? AnimatedBuilder(
                                  animation: _progress,
                                  builder: (context, _) =>
                                      FractionallySizedBox(
                                    alignment: AlignmentDirectional.centerStart,
                                    widthFactor: _progress.value,
                                    child: Container(color: Colors.white),
                                  ),
                                ) : const SizedBox.shrink(),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                Positioned(
                  top: 20,
                  left: 12,
                  right: 12,
                  child: Row(
                    children: [
                      // Author block: avatar + username on top, timestamp
                      // stacked underneath. Tap opens the author profile.
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _openAuthorProfile(story.authorUid),
                          child: Row(
                            children: [
                              Hero(
                                tag: 'story_avatar_${story.authorUid}',
                                child: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Colors.grey.shade700,
                                  backgroundImage: avatarUrl != null
                                      ? CachedNetworkImageProvider(avatarUrl)
                                      : null,
                                  child: avatarUrl == null
                                      ? const Icon(
                                          Icons.person,
                                          size: 18,
                                          color: Colors.white70,
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      username,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      context.t.timeAgo(story.createdAt),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.75),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _openShareSheet(story),
                        tooltip: context.t.share,
                        icon: const Icon(
                          Icons.ios_share,
                          color: Colors.white,
                        ),
                      ),
                      // Own stories show a direct trash icon — no overflow
                      // menu, no Close item. Back gesture / swipe down
                      // closes the viewer. Wears the same translucent
                      // black pill chrome as the views counter so the
                      // header reads as one design system.
                      if (isOwnStory)
                        GestureDetector(
                          onTap: _deleteCurrentStory,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            child: const Icon(
                              Icons.delete_outline,
                              color: Color(0xFFEF476F),
                              size: 20,
                            ),
                          ),
                        ),
                      // Always-available close button. Lives in the header
                      // (above the media + any loading spinner), so the user
                      // can leave the viewer even while a story is still
                      // loading — same exit as the swipe-down gesture.
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: _close,
                        tooltip: context.t.close,
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                // The old floating heart-like + comment-count column used to
                // sit at bottom+100 and overlapped the new reactions strip,
                // hiding all reactions except the heart. We merged the
                // story-level like into the reactions row (tap ❤️ both
                // toggles the story like AND DMs the author), so this
                // floating column is no longer needed.
                // Comment input
                Positioned(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  left: 16,
                  right: 16,
                  child: _currentUid == null
                      ? _StorySignInBanner()
                      : isOwnStory
                          ? const SizedBox.shrink()
                          : _StoryReplyComposer(
                              controller: _commentController,
                              focusNode: _commentFocusNode,
                              sending: _sendingComment,
                              storyId: story.id,
                              service: _storyService,
                              onSend: _addComment,
                              onHeartTap: () => _toggleLike(),
                            ),
                ),
                if (isOwnStory)
                  Positioned(
                    // Own stories have no reply composer, so the pills sit
                    // at the same low offset the composer would use.
                    bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        _ViewsPill(
                          storyId: story.id,
                          service: _storyService,
                          onTap: () => _showViewersSheet(story.id),
                        ),
                        const SizedBox(width: 8),
                        _LikesPill(
                          storyId: story.id,
                          service: _storyService,
                          onTap: () => _showLikersSheet(story.id),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }
}

class _ViewsPill extends StatelessWidget {
  final String storyId;
  final StoryService service;
  final VoidCallback onTap;
  const _ViewsPill({
    required this.storyId,
    required this.service,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StoryViewer>>(
      stream: service.streamViewers(storyId),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.remove_red_eye_outlined,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  count == 1
                      ? context.t.storyViewCount(count)
                      : context.t.storyViewsCount(count),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Likes counter shown next to [_ViewsPill] for the story owner. Tapping
/// opens [_LikersSheet] with the list of users who liked the story.
class _LikesPill extends StatelessWidget {
  final String storyId;
  final StoryService service;
  final VoidCallback onTap;
  const _LikesPill({
    required this.storyId,
    required this.service,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: service.streamLikesCount(storyId),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.favorite,
                  color: Color(0xFFFF3B5C),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  count == 1
                      ? context.t.storyLikeCount(count)
                      : context.t.storyLikesCount(count),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LikersSheet extends ConsumerWidget {
  final String storyId;
  final StoryService service;
  const _LikersSheet({required this.storyId, required this.service});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.textSecondary.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              StreamBuilder<int>(
                stream: service.streamLikesCount(storyId),
                builder: (context, snapshot) {
                  final count = snapshot.data ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.favorite,
                          size: 20,
                          color: Color(0xFFFF3B5C),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          count == 1
                              ? context.t.storyLikeCount(count)
                              : context.t.storyLikesCount(count),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<List<StoryViewer>>(
                  stream: service.streamLikers(storyId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final likers = snapshot.data ?? const [];
                    if (likers.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            context.t.storyNoLikesYet,
                            style: TextStyle(color: context.textSecondary),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: likers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final v = likers[i];
                        final userData =
                            ref.watch(userByUidProvider(v.uid)).value;
                        final avatarUrl = userData?['avatarUrl'] as String?;
                        final username =
                            userData?['username'] as String? ?? v.username;
                        return ListTile(
                          onTap: () {
                            Navigator.pop(context);
                            openUserProfile(context, uid: v.uid);
                          },
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: context.surfaceSoft,
                            backgroundImage: avatarUrl != null
                                ? CachedNetworkImageProvider(avatarUrl)
                                : null,
                            child: avatarUrl == null
                                ? Icon(
                                    Icons.person,
                                    size: 18,
                                    color: context.textSecondary,
                                  )
                                : null,
                          ),
                          title: Text(
                            username.isEmpty ? v.uid : username,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                            ),
                          ),
                          trailing: Text(
                            context.t.timeAgo(v.viewedAt),
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ViewersSheet extends ConsumerWidget {
  final String storyId;
  final StoryService service;
  const _ViewersSheet({required this.storyId, required this.service});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.textSecondary.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<StoryViewer>>(
                stream: service.streamViewers(storyId),
                builder: (context, snapshot) {
                  final count = snapshot.data?.length ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Icon(
                          Icons.remove_red_eye_outlined,
                          size: 20,
                          color: context.textPrimary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          count == 1
                              ? context.t.storyViewCount(count)
                              : context.t.storyViewsCount(count),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<List<StoryViewer>>(
                  stream: service.streamViewers(storyId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final viewers = snapshot.data ?? const [];
                    if (viewers.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            context.t.storyNoViewsYet,
                            style: TextStyle(color: context.textSecondary),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                      itemCount: viewers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final v = viewers[i];
                        final userData = ref.watch(userByUidProvider(v.uid)).value;
                        final avatarUrl = userData?['avatarUrl'] as String?;
                        final username =
                            userData?['username'] as String? ?? v.username;
                        return _ViewerCard(
                          avatarUrl: avatarUrl ?? '',
                          title: username.isEmpty ? v.uid : username,
                          trailingText: context.t.timeAgo(v.viewedAt),
                          onTap: () {
                            Navigator.pop(context);
                            openUserProfile(context, uid: v.uid);
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Story reply composer (input + heart like)
// ─────────────────────────────────────────────

/// Reply UI for the story viewer. A single pill-shaped input with a
/// heart on the LEFT (Instagram-style: taps toggle the story-level like
/// without sending anything to the chat) and a send button on the RIGHT
/// for private replies. Hidden when the viewer is looking at their own
/// story.
class _StoryReplyComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final String storyId;
  final StoryService service;
  final Future<void> Function() onSend;
  final Future<void> Function() onHeartTap;

  const _StoryReplyComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.storyId,
    required this.service,
    required this.onSend,
    required this.onHeartTap,
  });

  @override
  Widget build(BuildContext context) {
    // Stadium / pill shape — radius is half the row height so the ends
    // are fully circular regardless of how tall the input grows. Using
    // a fixed large radius (e.g. 28) looked square once the heart icon
    // pushed the row to ~52px tall.
    // The story viewer is always rendered on a dark backdrop (the story
    // image / shared-post card). The reply pill therefore uses fixed
    // light-on-translucent-dark styling regardless of the app's
    // light/dark theme — otherwise the global InputDecorationTheme
    // (filled = true, light grey fillColor) leaked through and produced
    // a milky-white rectangle inside the pill on light mode that hid
    // the user's typed text. Pinning `filled: false` and explicit white
    // text/hint colors guarantees readability either way.
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      // Horizontal padding needs to clear the stadium curve so the 40px
      // gradient send circle doesn't get clipped by the rounded end of
      // the pill (it was poking out on the leading side in RTL).
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: ShapeDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: StadiumBorder(
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.25),
          ),
        ),
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        // Center vertically so heart and send sit on the same baseline
        // as the (single-line) hint. When the input grows past one line
        // the buttons stay centered against the multi-line block, which
        // reads better than bottom-anchored icons that crowd the last
        // line of text.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Heart at the leading edge — toggles the story-level like
          // only. Does NOT DM the author; that was the old reactions
          // behavior the user removed.
          StreamBuilder<bool>(
            stream: service.streamIsLiked(storyId),
            builder: (context, snapshot) {
              final liked = snapshot.data ?? false;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  onHeartTap();
                },
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    color: liked ? const Color(0xFFFF3B5C) : Colors.white,
                    size: 24,
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              cursorColor: Colors.white,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              // Multi-line: user can press Enter for a newline; send is
              // the explicit purple button on the right. Keyboard shows
              // the newline action instead of "Send" because Send would
              // otherwise dismiss the input mid-thought.
              //
              // Cap the visible height at 2 lines — beyond that the
              // pill would start to dominate the story canvas. Anything
              // past 2 lines scrolls inside the field (TextField's
              // built-in scroll behavior kicks in once the content
              // exceeds maxLines).
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                fillColor: Colors.transparent,
                hintText: context.t.storyReplyPrivatelyHint,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              ),
            ),
          ),
          const SizedBox(width: 6),
          AnimatedScale(
            duration: const Duration(milliseconds: 150),
            scale: sending ? 0.92 : 1.0,
            child: GestureDetector(
              onTap: sending ? null : () => onSend(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: sending
                      ? null
                      : const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFCE5DE5), Color(0xFFB05ECC)],
                        ),
                  color: sending
                      ? Colors.white.withValues(alpha: 0.15)
                      : null,
                  shape: BoxShape.circle,
                  boxShadow: sending
                      ? const []
                      : [
                          BoxShadow(
                            color: const Color(0xFFB05ECC)
                                .withValues(alpha: 0.45),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown in place of the reply composer when no user is signed in.
class _StorySignInBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: ShapeDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: StadiumBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
        ),
      ),
      child: Center(
        child: Text(
          context.t.storySignInBanner,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
    );
  }
}

/// Renders a "shared post" story: the original feed/travel post shown
/// as a card centered on a brand-gradient background. Tapping the card
/// opens the full post in [PostDetailScreen].
/// Tappable "View event" pill overlaid on a shared-event story. Opens the
/// event detail via [openEventById].
class _ViewEventChip extends StatelessWidget {
  final String eventId;
  final String? title;

  const _ViewEventChip({required this.eventId, this.title});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openEventById(context, eventId),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_outlined, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null && title!.isNotEmpty)
                    Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  Text(
                    context.t.eventsViewEvent,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }
}

class _SharedPostStoryView extends ConsumerStatefulWidget {
  final String postId;

  const _SharedPostStoryView({required this.postId});

  @override
  ConsumerState<_SharedPostStoryView> createState() =>
      _SharedPostStoryViewState();
}

class _SharedPostStoryViewState extends ConsumerState<_SharedPostStoryView> {
  late Future<Post?> _postFuture;

  @override
  void initState() {
    super.initState();
    _postFuture = ref.read(postServiceProvider).getPostById(widget.postId);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF7E3BE8), Color(0xFFB05ECC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: FutureBuilder<Post?>(
        future: _postFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          final post = snap.data;
          if (post == null) {
            return Center(
              child: Text(
                context.t.postNotFound,
                style: const TextStyle(color: Colors.white),
              ),
            );
          }
          // Keep the centred card clear of the bottom controls — both the
          // reply composer (others' stories) and the views/likes pills
          // (own stories) sit at the same low bottom offset.
          return Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 96),
            child: Center(
              child: SingleChildScrollView(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PostDetailScreen(postId: post.id),
                    ),
                  ),
                  child: _SharedPostCard(post: post),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The post rendered as a compact card for the story background.
class _SharedPostCard extends StatelessWidget {
  final Post post;

  const _SharedPostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final hasImage = post.imageUrls.isNotEmpty;
    final hasVideo = !hasImage && post.videoUrls.isNotEmpty;
    final caption = post.caption.trim();

    return Container(
      decoration: BoxDecoration(
        color: context.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author row.
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: context.purpleSoft,
                  backgroundImage: (post.authorAvatar != null &&
                          post.authorAvatar!.isNotEmpty)
                      ? CachedNetworkImageProvider(post.authorAvatar!)
                      : null,
                  child: (post.authorAvatar == null ||
                          post.authorAvatar!.isEmpty)
                      ? Icon(Icons.person,
                          size: 16, color: context.textSecondary)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    post.authorUsername,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasImage)
            AspectRatio(
              aspectRatio: 1,
              child: CachedNetworkImage(
                imageUrl: post.imageUrls.first,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: context.surfaceSoft),
                errorWidget: (_, __, ___) =>
                    Container(color: context.surfaceSoft),
              ),
            )
          else if (hasVideo)
            // Video-only posts have no still image — show a dark tile
            // with a centered play icon so the story still has a media
            // affordance. The user can tap the card to open the post and
            // play the actual video.
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.7),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                caption,
                maxLines: hasImage ? 3 : 8,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: context.textPrimary,
                ),
              ),
            ),
          // Tap hint.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.touch_app_outlined,
                    size: 14, color: Color(0xFF7E3BE8)),
                const SizedBox(width: 4),
                Text(
                  context.t.storyTapToViewPost,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7E3BE8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Story share sheet — add to my story / send to friends / share via apps
// ─────────────────────────────────────────────

class _StoryShareSheet extends ConsumerWidget {
  final Story story;
  final Future<void> Function() onAddToMyStory;
  final Future<void> Function() onShareExternally;
  final Future<void> Function(
      String chatId, String otherUid, String title) onSendToChat;

  const _StoryShareSheet({
    required this.story,
    required this.onAddToMyStory,
    required this.onShareExternally,
    required this.onSendToChat,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: context.borderColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  context.t.share,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            // Quick action row: add-to-my-story + share-via-apps.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _ShareAction(
                      icon: Icons.add_circle_outline,
                      label: context.t.addToStory,
                      onTap: onAddToMyStory,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ShareAction(
                      icon: Icons.ios_share,
                      label: context.t.share,
                      onTap: onShareExternally,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: context.borderColor),
            // Friends / recent chats — tap to DM the story.
            Expanded(
              child: Consumer(
                builder: (context, ref, _) {
                  final inbox = ref.watch(acceptedInboxProvider);
                  return inbox.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) =>
                        Center(child: Text(context.t.errorWithMessage(e))),
                    data: (chats) {
                      if (chats.isEmpty) {
                        return Center(child: Text(context.t.noChatsYet));
                      }
                      return ListView.separated(
                        controller: scrollController,
                        padding:
                            const EdgeInsets.fromLTRB(14, 10, 14, 16),
                        itemCount: chats.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final c = chats[i];
                          final title =
                              c.isGroup ? c.groupName : c.otherUsername;
                          final avatar = c.isGroup
                              ? c.groupAvatarUrl
                              : c.otherAvatarUrl;
                          return _StoryShareRecipientCard(
                            avatarUrl: avatar,
                            title: title,
                            isGroup: c.isGroup,
                            onSend: () =>
                                onSendToChat(c.chatId, c.otherUid, title),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  const _ShareAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: context.inputFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.purpleSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: AppColors.purple, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modern rounded card used inside the story share sheet to list each
/// recipient. Mirrors the post-share card design so the two share surfaces
/// feel like one product.
class _StoryShareRecipientCard extends StatelessWidget {
  final String avatarUrl;
  final String title;
  final bool isGroup;
  final VoidCallback onSend;

  const _StoryShareRecipientCard({
    required this.avatarUrl,
    required this.title,
    required this.isGroup,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onSend,
        child: Ink(
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: context.borderColor.withValues(alpha: 0.6),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFB05ECC), Color(0xFF7E3BE8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.all(2),
                child: CircleAvatar(
                  backgroundColor: context.inputFill,
                  backgroundImage: avatarUrl.isNotEmpty
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? Icon(
                          isGroup ? Icons.group : Icons.person,
                          color: context.textSecondary,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onSend,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFB05ECC), Color(0xFF7E3BE8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFFB05ECC).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.t.postCardSend,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modern rounded card used in the "Viewers" sheet. Mirrors the share
/// sheet's recipient card design — same gradient avatar ring and card
/// chrome — but with a timestamp trailing instead of a Send button.
class _ViewerCard extends StatelessWidget {
  final String avatarUrl;
  final String title;
  final String trailingText;
  final VoidCallback onTap;

  const _ViewerCard({
    required this.avatarUrl,
    required this.title,
    required this.trailingText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: context.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: context.borderColor.withValues(alpha: 0.6),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFB05ECC), Color(0xFF7E3BE8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.all(2),
                child: CircleAvatar(
                  backgroundColor: context.inputFill,
                  backgroundImage: avatarUrl.isNotEmpty
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? Icon(Icons.person, color: context.textSecondary)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailingText,
                style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Video story player — auto-plays an inline video story on loop while
// the viewer is on that story. The progress ring in [StoryViewerScreen]
// still advances on its own 5s timer; we don't sync the two here.
// ─────────────────────────────────────────────

class _VideoStoryPlayer extends StatefulWidget {
  final String url;
  // Optional trim window. The uploaded video bytes aren't re-encoded
  // (Flutter has no built-in trimmer) — instead we clamp playback here:
  // start at [trimStart] and seek back to [trimStart] whenever playback
  // reaches [trimEnd]. Either may be null to mean "edge of video".
  final Duration? trimStart;
  final Duration? trimEnd;
  // Called once the video has loaded its first frame. The story viewer
  // uses this to delay starting the progress timer until the user can
  // actually see the video. The argument is the effective playback
  // duration (trim window if set, else full video length) so the
  // progress bar can run for the real video length instead of a fixed
  // 5s tick.
  final ValueChanged<Duration>? onReady;
  // While the bound notifier is `true`, the player pauses. The viewer
  // toggles it during long-press so the video freezes alongside the
  // progress bar.
  final ValueListenable<bool>? pausedNotifier;
  // Called on every playback tick with the current position as a
  // fraction of the effective playback window (0..1). Lets the viewer
  // drive the story progress bar straight from the video's clock so
  // the bar can never drift relative to the visible frames.
  final ValueChanged<double>? onPositionUpdate;
  // Called exactly once when the video reaches the end of its effective
  // playback window. The viewer uses this to advance to the next story.
  // We drive auto-advance from here (the controller's real position)
  // rather than from [onPositionUpdate] reaching 1.0, because the
  // polled progress fraction can miss the exact end frame and is purely
  // for the visual bar.
  final VoidCallback? onCompleted;
  const _VideoStoryPlayer({
    super.key,
    required this.url,
    this.trimStart,
    this.trimEnd,
    this.onReady,
    this.pausedNotifier,
    this.onPositionUpdate,
    this.onCompleted,
  });

  @override
  State<_VideoStoryPlayer> createState() => _VideoStoryPlayerState();
}

class _VideoStoryPlayerState extends State<_VideoStoryPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _failed = false;
  // Cached effective trim window resolved against the actual video
  // duration once `initialize()` returns.
  Duration _effectiveStart = Duration.zero;
  Duration _effectiveEnd = Duration.zero;
  // True once we've fired [onCompleted] for this playback so the
  // end-of-window detection can't advance the story more than once
  // (the listener and the position timer can both observe the end).
  bool _completed = false;
  // Polls `c.value.position` every ~60ms to feed the story progress
  // bar. VideoPlayerController.addListener only fires on coarse state
  // changes (not on every painted frame), so the progress bar was
  // ticking jerkily / appearing not to move. A periodic poll gives the
  // bar a smooth 60ms update cadence regardless of platform.
  Timer? _positionTimer;
  // Last known playhead position. Remembered across app-background so
  // we can resume where the user left off after recreating the
  // controller on AppLifecycleState.resumed.
  Duration _lastKnownPosition = Duration.zero;
  // True while we've torn down the codec because the app went to
  // background. The next `resumed` event recreates the controller; we
  // also short-circuit `build` to a spinner so the broken-image
  // placeholder doesn't flash in.
  bool _suspended = false;
  // Guards against overlapping setup calls — `initialize()` is async
  // and the lifecycle observer can fire while one is in flight,
  // racing on `_controller`.
  bool _setupInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.pausedNotifier?.addListener(_onPausedChanged);
    _setup();
  }

  Future<void> _setup({Duration resumeFrom = Duration.zero}) async {
    if (_setupInFlight) return;
    _setupInFlight = true;
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      _controller = c;
      final total = c.value.duration;
      _effectiveStart = (widget.trimStart ?? Duration.zero);
      _effectiveEnd = (widget.trimEnd ?? total);
      if (_effectiveStart < Duration.zero) _effectiveStart = Duration.zero;
      if (_effectiveEnd > total) _effectiveEnd = total;
      if (_effectiveEnd <= _effectiveStart) {
        // Defensive: malformed trim window — fall back to full video.
        _effectiveStart = Duration.zero;
        _effectiveEnd = total;
      }
      // Never loop natively. A story video should play once and then
      // auto-advance to the next story; native looping made it replay
      // (and, after the first wraparound, the codec surface ended up in
      // a bad state showing a black frame). End-of-window is detected in
      // [_onTick] which fires [onCompleted] exactly once.
      final hasTrim =
          widget.trimStart != null || widget.trimEnd != null;
      await c.setLooping(false);
      // Pick a seek target: the explicit resume position from the
      // lifecycle handler wins; otherwise honor the trim start.
      final seekTarget = resumeFrom > Duration.zero
          ? (resumeFrom > _effectiveEnd ? _effectiveStart : resumeFrom)
          : (hasTrim ? _effectiveStart : null);
      if (seekTarget != null) {
        await c.seekTo(seekTarget);
      }
      // Tick listener handles trim wraparound (seek back to start when
      // the playhead reaches the trim end). Position updates for the
      // story progress bar are driven by the periodic timer below
      // because the controller's listener only fires on coarse state
      // changes and produced a jerky / stuck bar.
      c.addListener(_onTick);
      // Honor a paused-at-mount state (rare but possible if the user
      // long-presses while the next story is still loading).
      if (widget.pausedNotifier?.value == true) {
        await c.pause();
      } else {
        await c.play();
      }
      _startPositionTimer();
      // Tell the viewer the first frame is ready so it can start the
      // progress timer (sized to the effective playback window). On a
      // post-resume recreate we skip this — the parent's progress bar
      // is already running off the previous onReady callback and
      // re-arming it would restart the timer from zero.
      if (resumeFrom == Duration.zero) {
        final effective = _effectiveEnd - _effectiveStart;
        widget.onReady?.call(effective);
      }
      if (mounted) setState(() => _suspended = false);
    } catch (_) {
      // Even on failure, signal "ready" so the viewer doesn't sit on a
      // spinner forever — the broken-image placeholder will render and
      // the timer will advance to the next story. Use the default
      // story tick when we have no real duration to report.
      if (resumeFrom == Duration.zero) {
        widget.onReady?.call(_kStoryDuration);
      }
      if (mounted) setState(() => _failed = true);
    } finally {
      _setupInFlight = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android releases the video codec's output surface when the
    // activity is backgrounded; coming back, `VideoPlayerController`
    // is stuck on a black frame even though it still reports
    // `isInitialized=true`. So on `paused` we tear the controller
    // down, and on `resumed` we rebuild it from the last known
    // position.
    //
    // We deliberately do NOT react to `inactive` or `hidden` — those
    // fire on transient focus loss (notification shade, permission
    // dialogs, transient overlays) and tearing the codec down every
    // time was overly aggressive and produced visible glitches.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final c = _controller;
      if (c != null && c.value.isInitialized) {
        _lastKnownPosition = c.value.position;
      }
      _stopPositionTimer();
      _controller?.removeListener(_onTick);
      unawaited(_controller?.dispose() ?? Future.value());
      _controller = null;
      if (mounted) setState(() => _suspended = true);
    } else if (state == AppLifecycleState.resumed && _suspended) {
      unawaited(_setup(resumeFrom: _lastKnownPosition));
    }
  }

  void _onPausedChanged() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final paused = widget.pausedNotifier?.value ?? false;
    if (paused) {
      try {
        c.pause();
      } catch (_) {}
    } else {
      try {
        c.play();
      } catch (_) {}
    }
  }

  void _onTick() {
    // The controller listener fires only on coarse state changes. We use
    // it as one of two completion signals; the periodic position timer
    // (`_onFrame`) is the other, because on iOS the listener doesn't
    // reliably fire a tick exactly at end-of-file.
    _maybeComplete();
  }

  /// Detects the end of the effective playback window and advances the
  /// story exactly once. Called from BOTH the controller listener
  /// (`_onTick`) and the 60ms position timer (`_onFrame`) — whichever
  /// observes the end first wins, and the `_completed` guard makes the
  /// other a no-op.
  void _maybeComplete() {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _completed) return;
    final v = c.value;
    // Three independent end signals, any of which means "done":
    //  - playhead crossed the (possibly trimmed) end of the window
    //  - the plugin's explicit end-of-file flag
    //  - the controller stopped playing at/near the full duration
    //    (iOS sometimes parks `position` a few ms short of `duration`
    //    and clears `isPlaying` instead of setting `isCompleted`)
    final pos = v.position;
    final nearFullEnd = !v.isPlaying &&
        v.duration > Duration.zero &&
        pos >= v.duration - const Duration(milliseconds: 250);
    final reachedEnd = pos >= _effectiveEnd || v.isCompleted || nearFullEnd;
    if (!reachedEnd) return;
    _completed = true;
    // Pin the progress bar to full so it doesn't visibly snap back.
    widget.onPositionUpdate?.call(1.0);
    widget.onCompleted?.call();
  }

  /// Drives the story progress bar at ~60ms cadence. We deliberately
  /// do NOT use `scheduleFrameCallback` to re-arm — that runs once per
  /// vsync (~16ms on 60Hz) and asserts inside `SchedulerBinding` if
  /// rescheduling outside a frame phase, which surfaced as a
  /// "Exception caught by scheduler library" crash mid-playback. The
  /// raw video `position` only updates a few times per second on
  /// Android, so between native ticks we extrapolate using wall-clock
  /// delta from the last reported position.
  Duration _lastReportedPos = Duration.zero;
  DateTime _lastReportedAt = DateTime.now();

  void _startPositionTimer() {
    _stopPositionTimer();
    _lastReportedPos = _controller?.value.position ?? Duration.zero;
    _lastReportedAt = DateTime.now();
    _positionTimer = Timer.periodic(
      const Duration(milliseconds: 60),
      (_) => _onFrame(),
    );
  }

  void _onFrame() {
    if (!mounted) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    // Always check for completion, even if no progress callback is wired.
    _maybeComplete();
    final cb = widget.onPositionUpdate;
    if (cb == null) return;
    final nativePos = c.value.position;
    // If the native position has advanced, snap our anchor to it. If
    // it hasn't (between native ticks), extrapolate by the wall-clock
    // delta since the last native update — but only while the
    // controller reports `isPlaying`, so a paused video freezes the
    // bar instead of drifting.
    final now = DateTime.now();
    Duration effectivePos;
    if (nativePos != _lastReportedPos) {
      _lastReportedPos = nativePos;
      _lastReportedAt = now;
      effectivePos = nativePos;
    } else if (c.value.isPlaying) {
      final wallDelta = now.difference(_lastReportedAt);
      effectivePos = _lastReportedPos + wallDelta;
    } else {
      effectivePos = nativePos;
    }
    if (effectivePos > _effectiveEnd) effectivePos = _effectiveEnd;
    final windowMs = (_effectiveEnd - _effectiveStart).inMilliseconds;
    if (windowMs > 0) {
      final intoMs = (effectivePos - _effectiveStart).inMilliseconds;
      final frac = (intoMs / windowMs).clamp(0.0, 1.0);
      cb(frac);
    }
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPositionTimer();
    widget.pausedNotifier?.removeListener(_onPausedChanged);
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
        child: Icon(Icons.broken_image, color: Colors.white),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      // Covers both the initial-load case and the brief window after a
      // post-resume recreate before `initialize()` returns. Showing a
      // spinner here also masks the dark frame that used to leak
      // through when the codec surface was released on backgrounding.
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    // Fill the whole screen (cover), cropping any overflow, so a portrait
    // video has no black bars at the edges — same as Instagram / TikTok
    // stories. `FittedBox(cover)` scales the video's native-sized box up
    // until it covers the viewport; `clipBehavior` trims the overflow.
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: c.value.size.width,
          height: c.value.size.height,
          child: VideoPlayer(c),
        ),
      ),
    );
  }
}

/// Background + centered text for a text-only story. Matches the look of
/// the [TextStoryComposerScreen] preview, including the optional text
/// border / shape selected at compose time.
class _TextStoryBackground extends StatelessWidget {
  final String text;
  final Color backgroundColor;
  final Color textColor;
  final String borderStyle;

  const _TextStoryBackground({
    required this.text,
    required this.backgroundColor,
    required this.textColor,
    this.borderStyle = 'none',
  });

  @override
  Widget build(BuildContext context) {
    final textWidget = Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: textColor,
        fontSize: 28,
        height: 1.25,
        fontWeight: FontWeight.w700,
      ),
    );
    return Container(
      color: backgroundColor,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
      child: StoryTextShape(
        style: borderStyle,
        bg: backgroundColor,
        textColor: textColor,
        child: textWidget,
      ),
    );
  }
}
