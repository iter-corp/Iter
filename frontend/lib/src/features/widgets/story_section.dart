import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/story_providers.dart';
import '../../navigation/user_profile_nav.dart';
import '../../services/story_service.dart';
import '../../theme/app_theme.dart';
import '../screens/camera_story_screen.dart';
import '../screens/story_viewer_screen.dart';

class StoriesList extends ConsumerStatefulWidget {
  const StoriesList({super.key});

  @override
  ConsumerState<StoriesList> createState() => _StoriesListState();
}

class _StoriesListState extends ConsumerState<StoriesList> {
  /// Tracks which authors have all stories viewed by current user.
  final Map<String, bool> _seenByAuthor = {};

  Future<void> _computeSeen(
    Map<String, List<Story>> byAuthor,
    String currentUid,
  ) async {
    final storyService = ref.read(storyServiceProvider);
    for (final entry in byAuthor.entries) {
      if (entry.key == currentUid) continue;
      // Author is "seen" only if ALL their stories have been viewed.
      bool allSeen = true;
      for (final story in entry.value) {
        final viewed = await storyService.hasViewed(story.id);
        if (!viewed) {
          allSeen = false;
          break;
        }
      }
      if (mounted && _seenByAuthor[entry.key] != allSeen) {
        setState(() => _seenByAuthor[entry.key] = allSeen);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final storiesAsync = ref.watch(activeStoriesProvider);
    final user = ref.watch(currentUserDocProvider).value;

    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: storiesAsync.when(
        loading: () => _skeleton(user),
        error: (_, __) => _skeleton(user),
        data: (stories) {
          // Group by author (stories are already oldest-first).
          final byAuthor = <String, List<Story>>{};
          for (final s in stories) {
            byAuthor.putIfAbsent(s.authorUid, () => []).add(s);
          }

          final currentUid = user?['uid'] as String? ?? '';

          // Compute seen state asynchronously.
          _computeSeen(byAuthor, currentUid);

          // Sort authors: unseen first, then seen.
          final otherAuthors =
              byAuthor.entries.where((e) => e.key != currentUid).toList();
          otherAuthors.sort((a, b) {
            final aSeen = _seenByAuthor[a.key] ?? false;
            final bSeen = _seenByAuthor[b.key] ?? false;
            if (aSeen != bSeen) return aSeen ? 1 : -1;
            // Within same seen-status, newest story author first.
            return b.value.last.createdAt.compareTo(a.value.last.createdAt);
          });

          // Build ordered groups list for cross-user swipe navigation.
          final allGroups = <List<Story>>[];
          final hasOwnStory = byAuthor.containsKey(currentUid);
          if (hasOwnStory) allGroups.add(byAuthor[currentUid]!);
          for (final entry in otherAuthors) {
            allGroups.add(entry.value);
          }

          return ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _MyStoryBubble(
                avatarUrl: user?['avatarUrl'] as String?,
                hasStory: hasOwnStory,
                stories: byAuthor[currentUid] ?? const [],
                allGroups: allGroups,
                groupIndex: 0,
              ),
              ...List.generate(otherAuthors.length, (i) {
                final entry = otherAuthors[i];
                final groupIndex = (hasOwnStory ? 1 : 0) + i;
                return _StoryBubble(
                  stories: entry.value,
                  seen: _seenByAuthor[entry.key] ?? false,
                  allGroups: allGroups,
                  groupIndex: groupIndex,
                );
              }),
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
          allGroups: const [],
          groupIndex: 0,
        ),
      ],
    );
  }
}

class _MyStoryBubble extends StatelessWidget {
  final String? avatarUrl;
  final bool hasStory;
  final List<Story> stories;
  final List<List<Story>> allGroups;
  final int groupIndex;
  const _MyStoryBubble({
    required this.avatarUrl,
    required this.hasStory,
    required this.stories,
    required this.allGroups,
    required this.groupIndex,
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
                openStoryViewer(context, allGroups, groupIndex);
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
                        ? Border.all(color: const Color(0xFFB05ECC), width: 2.5)
                        : null,
                  ),
                  child: Hero(
                    tag: hasStory && stories.isNotEmpty
                        ? 'story_avatar_${stories.first.authorUid}'
                        : 'story_avatar_me_${avatarUrl ?? 'none'}',
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: context.inputFill,
                      backgroundImage: avatarUrl != null
                          ? CachedNetworkImageProvider(avatarUrl!)
                          : null,
                      child: avatarUrl == null
                          ? Icon(Icons.person, color: context.textMuted)
                          : null,
                    ),
                  ),
                ),
                if (!hasStory)
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB05ECC),
                      shape: BoxShape.circle,
                      border: Border.all(color: context.cardBg, width: 2),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 14),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text('Your story',
              style: TextStyle(fontSize: 11, color: context.textSecondary)),
        ],
      ),
    );
  }
}

class _StoryBubble extends ConsumerWidget {
  final List<Story> stories;
  final bool seen;
  final List<List<Story>> allGroups;
  final int groupIndex;
  const _StoryBubble({
    required this.stories,
    this.seen = false,
    required this.allGroups,
    required this.groupIndex,
  });

  void _openStory(BuildContext context) {
    openStoryViewer(context, allGroups, groupIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = stories.first;
    final userData = ref.watch(userByUidProvider(first.authorUid)).value;
    final avatarUrl = userData?['avatarUrl'] as String?;
    final username = userData?['username'] as String? ?? first.authorUsername;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _openStory(context),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: seen ? context.borderColor : const Color(0xFFB05ECC),
                  width: 2.5,
                ),
              ),
              child: Hero(
                tag: 'story_avatar_${first.authorUid}',
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: context.inputFill,
                  backgroundImage: avatarUrl != null
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl == null
                      ? Icon(Icons.person, color: context.textMuted)
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 70,
            child: GestureDetector(
              onTap: () => openUserProfile(context, uid: first.authorUid),
              child: Text(
                username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: context.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
