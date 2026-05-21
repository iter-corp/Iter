import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../navigation/user_profile_nav.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../providers/post_providers.dart';
import '../../services/story_service.dart';
import '../../theme/app_theme.dart';
import '../model/post_model.dart';
import 'post_detail_screen.dart';

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
  /// input (typing a reply) and resumes when they unfocus, so the story
  /// doesn't move on while they're mid-message.
  void _onReplyFocusChange() {
    if (!mounted) return;
    if (_commentFocusNode.hasFocus) {
      _progress.stop();
    } else {
      _progress.forward();
    }
  }

  @override
  void dispose() {
    _commentFocusNode.removeListener(_onReplyFocusChange);
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
    // fast taps through stories are still counted.
    _storyService
        .recordView(story.id, authorUid: story.authorUid)
        .catchError((Object e, StackTrace _) {
      debugPrint('recordView failed for ${story.id}: $e');
    });

    try {
      await precacheImage(
        CachedNetworkImageProvider(story.imageUrl),
        context,
      );
    } catch (_) {
      // Fall through — still start the timer so the viewer never locks up.
    }
    if (!mounted || _loadingForStoryId != story.id) return;
    _progress.forward(from: 0);
  }

  void _next() {
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

  void _nextGroup() {
    if (_groupIndex < _allGroups.length - 1) {
      setState(() {
        _groupIndex++;
        _index = 0;
      });
      _startCurrent();
    } else {
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
    }
  }

  Future<void> _openAuthorProfile(String uid) async {
    _progress.stop();
    await openUserProfile(context, uid: uid);
    if (mounted) _progress.forward();
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
    if (mounted) _progress.forward();
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
    if (mounted) _progress.forward();
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
      _progress.forward();
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
      _progress.forward();
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
    final isOwnStory = story.authorUid == _currentUid;
    final width = MediaQuery.of(context).size.width;
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
              if (details.globalPosition.dx < width / 3) {
                _prev();
              } else {
                _next();
              }
            },
          onLongPressStart: (_) => _progress.stop(),
          onLongPressEnd: (_) => _progress.forward(),
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) > 200) {
              Navigator.pop(context);
            }
          },
          onHorizontalDragEnd: (details) {
            final v = details.primaryVelocity ?? 0;
            if (v < -200) {
              _nextGroup();
            } else if (v > 200) {
              _prevGroup();
            }
          },
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: story.sharedPostId != null &&
                          story.sharedPostId!.isNotEmpty
                      ? _SharedPostStoryView(postId: story.sharedPostId!)
                      : CachedNetworkImage(
                          imageUrl: story.imageUrl,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const Center(
                            child: CircularProgressIndicator(
                                color: Colors.white),
                          ),
                          errorWidget: (_, __, ___) => const Center(
                            child:
                                Icon(Icons.broken_image, color: Colors.white),
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
                      GestureDetector(
                        onTap: () => _openAuthorProfile(story.authorUid),
                        child: Row(
                          children: [
                            Hero(
                              tag: 'story_avatar_${story.authorUid}',
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.grey.shade700,
                                backgroundImage: avatarUrl != null
                                    ? CachedNetworkImageProvider(
                                        avatarUrl,
                                      )
                                    : null,
                                child: avatarUrl == null
                                    ? const Icon(
                                        Icons.person,
                                        size: 16,
                                        color: Colors.white70,
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              username,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              context.t.timeAgo(story.createdAt),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (isOwnStory)
                        IconButton(
                          onPressed: _deleteCurrentStory,
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.white,
                          ),
                        ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
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
                      itemCount: viewers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final v = viewers[i];
                        final userData = ref.watch(userByUidProvider(v.uid)).value;
                        final avatarUrl = userData?['avatarUrl'] as String?;
                        final username = userData?['username'] as String? ?? v.username;
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
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: ShapeDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: StadiumBorder(
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.22),
          ),
        ),
      ),
      child: Row(
        children: [
          // Heart on the left — toggles the story-level like only. Does
          // NOT DM the author; that was the old reactions behavior the
          // user removed.
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
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
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
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                isDense: true,
                hintText: context.t.storyReplyPrivatelyHint,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: sending ? null : () => onSend(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sending
                    ? Colors.white.withValues(alpha: 0.15)
                    : const Color(0xFFB05ECC),
                shape: BoxShape.circle,
              ),
              child: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send, color: Colors.white, size: 18),
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
