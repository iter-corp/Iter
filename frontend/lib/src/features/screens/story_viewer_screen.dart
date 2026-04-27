import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../navigation/user_profile_nav.dart';
import '../../providers/auth_providers.dart';
import '../../providers/chat_providers.dart';
import '../../services/story_service.dart';

/// Quick-reaction emojis shown above the story reply input. Tapping any of
/// these sends a private DM to the story author with the emoji + a story
/// reference (so the chat bubble shows which story it was about).
const List<String> _kStoryQuickReactions = [
  '❤️', '🔥', '😂', '😮', '👏', '😢', '🙌',
];

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

  List<Story> get _stories => _allGroups[_groupIndex];

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.initialGroupIndex;
    _allGroups = widget.allGroups.map((g) => List<Story>.of(g)).toList();
    _progress = AnimationController(
      vsync: this,
      duration: _kStoryDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _next();
        }
      });
    _commentFocusNode.addListener(_onReplyFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCurrent());
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
    final story = _stories[_index];
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to like stories')),
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
          SnackBar(content: Text('Failed to toggle like: $e')),
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
        const SnackBar(content: Text('Reply sent')),
      );
    }
  }

  /// Sends a quick emoji reaction to the story author as a DM. Same flow as
  /// [_replyToStoryAsDM] but with an emoji as the text. The receiving chat
  /// renders a "Replied to your story" header above the bubble so the
  /// recipient knows which story the reaction is about. Tapping ❤️ also
  /// toggles the story-level like so the engagement counter updates.
  Future<void> _quickReact(String emoji) async {
    HapticFeedback.lightImpact();
    debugPrint('[story-react] tapped emoji=$emoji story=${_stories[_index].id}');
    final ok = await _replyToStoryAsDM(emoji);
    debugPrint('[story-react] DM result=$ok');
    if (emoji == '❤️' && _currentUid != null && !_isLiking) {
      // Fire-and-forget — silenced so the DM "Sent ❤️" toast isn't
      // followed by a permission-denied banner from the like attempt.
      unawaited(_toggleLike(silent: true));
    }
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sent $emoji'),
        duration: const Duration(milliseconds: 900),
      ),
    );
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
    final story = _stories[_index];
    final me = _currentUid;
    debugPrint('[story-reply] me=$me author=${story.authorUid} '
        'storyId=${story.id} text="${trimmed.length > 30 ? "${trimmed.substring(0, 30)}…" : trimmed}"');
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to reply to stories')),
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
        SnackBar(content: Text('Failed to send reply: $e')),
      );
      return false;
    }
  }

  Future<void> _startCurrent() async {
    final story = _stories[_index];
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

  Future<void> _deleteCurrentStory() async {
    final story = _stories[_index];
    _progress.stop();
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete story?'),
        content: const Text('This will remove the story for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
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
        _allGroups[_groupIndex].removeAt(_index);
        if (_stories.isNotEmpty && _index >= _stories.length) {
          _index = _stories.length - 1;
        }
      });

      if (_stories.isEmpty) {
        Navigator.pop(context);
        return;
      }

      _startCurrent();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
      _progress.forward();
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final story = _stories[_index];
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
                  child: CachedNetworkImage(
                    imageUrl: story.imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image, color: Colors.white),
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
                                    alignment: Alignment.centerLeft,
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
                              _timeAgo(story.createdAt),
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
                              onSend: _addComment,
                              onReact: _quickReact,
                            ),
                ),
                if (isOwnStory)
                  Positioned(
                    bottom: MediaQuery.of(context).viewInsets.bottom + 140, // Moved higher to avoid overlap with comment input
                    left: 16,
                    right: 16,
                    child: _ViewsPill(
                      storyId: story.id,
                      service: _storyService,
                      onTap: () => _showViewersSheet(story.id),
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
                  '$count ${count == 1 ? 'view' : 'views'}',
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

class _ViewersSheet extends ConsumerWidget {
  final String storyId;
  final StoryService service;
  const _ViewersSheet({required this.storyId, required this.service});

  String _ago(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
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
                        const Icon(
                          Icons.remove_red_eye_outlined,
                          size: 20,
                          color: Colors.black87,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$count ${count == 1 ? 'view' : 'views'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
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
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No views yet',
                            style: TextStyle(color: Colors.grey),
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
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: avatarUrl != null
                                ? CachedNetworkImageProvider(avatarUrl)
                                : null,
                            child: avatarUrl == null
                                ? const Icon(
                                    Icons.person,
                                    size: 18,
                                    color: Colors.grey,
                                  )
                                : null,
                          ),
                          title: Text(
                            username.isEmpty ? v.uid : username,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: Text(
                            _ago(v.viewedAt),
                            style: const TextStyle(
                              color: Colors.grey,
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
// Story reply composer (input + quick-reactions)
// ─────────────────────────────────────────────

/// Modern reply UI for the story viewer. Two stacked rows:
///   1. Quick-reactions strip — one-tap emojis that DM the story author
///   2. Pill-shaped text input + send button
/// Designed to read clearly over photo backgrounds (translucent dark fill,
/// soft purple accents, white text). Hidden when the viewer is looking at
/// their own story.
class _StoryReplyComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final Future<void> Function() onSend;
  final Future<void> Function(String emoji) onReact;

  const _StoryReplyComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Quick-reactions row — every emoji always visible, evenly spread
        // across the full input width. We use a Row with Expanded children
        // (not a horizontal ListView) so reactions can never collapse to
        // zero width or get hidden behind a sibling Positioned widget.
        Row(
          children: [
            for (final emoji in _kStoryQuickReactions)
              Expanded(
                child: GestureDetector(
                  onTap: () => onReact(emoji),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 44,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Input pill.
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            children: [
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
                    hintText: 'Reply privately…',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
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
        ),
      ],
    );
  }
}

/// Shown in place of the reply composer when no user is signed in.
class _StorySignInBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: const Center(
        child: Text(
          'Sign in to reply to stories',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
    );
  }
}
