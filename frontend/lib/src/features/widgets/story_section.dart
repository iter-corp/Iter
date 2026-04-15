import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/story_providers.dart';
import '../../services/story_service.dart';
import '../screens/camera_story_screen.dart';
import '../screens/story_viewer_screen.dart';

class StoriesList extends ConsumerWidget {
  const StoriesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storiesAsync = ref.watch(activeStoriesProvider);
    final user = ref.watch(currentUserDocProvider).value;

    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: storiesAsync.when(
        loading: () => _skeleton(user),
        error: (_, __) => _skeleton(user),
        data: (stories) {
          // Group by author
          final byAuthor = <String, List<Story>>{};
          for (final s in stories) {
            byAuthor.putIfAbsent(s.authorUid, () => []).add(s);
          }

          // Entries: own story (tap to create) first, then others.
          return ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _MyStoryBubble(
                avatarUrl: user?['avatarUrl'] as String?,
                hasStory: user != null &&
                    byAuthor.containsKey(user['uid'] ?? ''),
                stories: byAuthor[user?['uid']] ?? const [],
              ),
              ...byAuthor.entries
                  .where((e) => e.key != (user?['uid'] ?? ''))
                  .map((entry) => _StoryBubble(stories: entry.value)),
            ],
          );
        },
      ),
    );
  }

  Widget _skeleton(Map<String, dynamic>? user) {
    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
        _MyStoryBubble(
          avatarUrl: user?['avatarUrl'] as String?,
          hasStory: false,
          stories: const [],
        ),
      ],
    );
  }
}

class _MyStoryBubble extends StatelessWidget {
  final String? avatarUrl;
  final bool hasStory;
  final List<Story> stories;
  const _MyStoryBubble({
    required this.avatarUrl,
    required this.hasStory,
    required this.stories,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              if (hasStory) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StoryViewerScreen(stories: stories),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CameraStoryScreen(),
                  ),
                );
              }
            },
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: hasStory
                        ? Border.all(
                            color: const Color(0xFFB05ECC), width: 2.5)
                        : null,
                  ),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: avatarUrl != null
                        ? CachedNetworkImageProvider(avatarUrl!)
                        : null,
                    child: avatarUrl == null
                        ? const Icon(Icons.person, color: Colors.grey)
                        : null,
                  ),
                ),
                if (!hasStory)
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB05ECC),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.add,
                        color: Colors.white, size: 14),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text('Your story',
              style: TextStyle(fontSize: 11, color: Colors.black87)),
        ],
      ),
    );
  }
}

class _StoryBubble extends StatelessWidget {
  final List<Story> stories;
  const _StoryBubble({required this.stories});

  @override
  Widget build(BuildContext context) {
    final first = stories.first;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StoryViewerScreen(stories: stories),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFFB05ECC), width: 2.5),
              ),
              child: CircleAvatar(
                radius: 30,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: first.authorAvatar != null
                    ? CachedNetworkImageProvider(first.authorAvatar!)
                    : null,
                child: first.authorAvatar == null
                    ? const Icon(Icons.person, color: Colors.grey)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 70,
            child: Text(
              first.authorUsername,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
