import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../navigation/user_profile_nav.dart';
import '../../services/story_service.dart';

const Duration _kStoryDuration = Duration(seconds: 5);

Future<T?> openStoryViewer<T>(
  BuildContext context,
  List<Story> stories,
) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 450),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => StoryViewerScreen(stories: stories),
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

class StoryViewerScreen extends StatefulWidget {
  final List<Story> stories;
  const StoryViewerScreen({super.key, required this.stories});

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  late final List<Story> _stories;
  final StoryService _storyService = StoryService();
  late final AnimationController _progress;
  String? _loadingForStoryId;

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _stories = List<Story>.of(widget.stories);
    _progress = AnimationController(
      vsync: this,
      duration: _kStoryDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _next();
        }
      });
    WidgetsBinding.instance.addPostFrameCallback((_) => _startCurrent());
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Future<void> _startCurrent() async {
    final story = _stories[_index];
    _progress.stop();
    _progress.value = 0;
    _loadingForStoryId = story.id;
    try {
      await precacheImage(
        CachedNetworkImageProvider(story.imageUrl),
        context,
      );
    } catch (_) {
      // Fall through — still start the timer so the viewer never locks up.
    }
    if (!mounted || _loadingForStoryId != story.id) return;
    _storyService.recordView(story.id).catchError((_) {});
    _progress.forward(from: 0);
  }

  void _next() {
    if (_index < _stories.length - 1) {
      setState(() => _index++);
      _startCurrent();
    } else {
      if (mounted) Navigator.pop(context);
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
    }
    _startCurrent();
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
      useSafeArea: true,
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
        _stories.removeAt(_index);
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTapUp: (details) {
            if (details.globalPosition.dx < width / 3) {
              _prev();
            } else {
              _next();
            }
          },
          onLongPressStart: (_) => _progress.stop(),
          onLongPressEnd: (_) => _progress.forward(),
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
                                if (i < _index)
                                  Container(color: Colors.white)
                                else if (i == _index)
                                  AnimatedBuilder(
                                    animation: _progress,
                                    builder: (context, _) =>
                                        FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: _progress.value,
                                      child: Container(color: Colors.white),
                                    ),
                                  ),
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
                                backgroundImage: story.authorAvatar != null
                                    ? CachedNetworkImageProvider(
                                        story.authorAvatar!,
                                      )
                                    : null,
                                child: story.authorAvatar == null
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
                              story.authorUsername,
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
                if (isOwnStory)
                  Positioned(
                    bottom: 20,
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

class _ViewersSheet extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                        return ListTile(
                          onTap: () {
                            Navigator.pop(context);
                            openUserProfile(context, uid: v.uid);
                          },
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: v.avatarUrl != null
                                ? CachedNetworkImageProvider(v.avatarUrl!)
                                : null,
                            child: v.avatarUrl == null
                                ? const Icon(
                                    Icons.person,
                                    size: 18,
                                    color: Colors.grey,
                                  )
                                : null,
                          ),
                          title: Text(
                            v.username.isEmpty ? v.uid : v.username,
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
