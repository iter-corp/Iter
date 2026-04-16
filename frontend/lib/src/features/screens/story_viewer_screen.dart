import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../navigation/user_profile_nav.dart';
import '../../services/story_service.dart';

class StoryViewerScreen extends StatefulWidget {
  final List<Story> stories;
  const StoryViewerScreen({super.key, required this.stories});

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  int _index = 0;
  Timer? _timer;
  late final List<Story> _stories;
  final StoryService _storyService = StoryService();
  static const _duration = Duration(seconds: 5);

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _stories = List<Story>.of(widget.stories);
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer(_duration, _next);
  }

  void _next() {
    if (_index < _stories.length - 1) {
      setState(() => _index++);
      _start();
    } else {
      if (mounted) Navigator.pop(context);
    }
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
      _start();
    }
  }

  Future<void> _openAuthorProfile(String uid) async {
    _timer?.cancel();
    await openUserProfile(context, uid: uid);
    if (mounted) {
      _start();
    }
  }

  Future<void> _deleteCurrentStory() async {
    final story = _stories[_index];
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
      _start();
      return;
    }

    _timer?.cancel();

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

      _start();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
      _start();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final story = _stories[_index];
    final isOwnStory = story.authorUid == _currentUid;
    final width = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (details) {
          if (details.globalPosition.dx < width / 3) {
            _prev();
          } else {
            _next();
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
              // Progress bars
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
                        decoration: BoxDecoration(
                          color: i < _index
                              ? Colors.white
                              : i == _index
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              // Header
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
                          CircleAvatar(
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
                          const SizedBox(width: 8),
                          Text(
                            story.authorUsername,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
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
            ],
          ),
        ),
      ),
    );
  }
}
