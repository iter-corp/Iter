import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which of the *current device user's own* stories the user has
/// already viewed. Stored locally on the device — own-story views are
/// intentionally NOT written to Firestore (the viewers list would
/// include the author, which Instagram-style social UX hides), so we
/// need a side channel to dim the ring on the home rail once the
/// author has flipped through their own stories.
///
/// Keyed by story id. Values are kept until the story expires (24h)
/// and clean themselves up when the story doc disappears from
/// `activeStoriesProvider`; we don't need a sweeper.
class OwnStorySeenService {
  static const _prefix = 'own_story_seen_';

  Future<bool> isSeen(String storyId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$storyId') ?? false;
  }

  Future<void> markSeen(String storyId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$storyId', true);
  }
}

final ownStorySeenServiceProvider =
    Provider<OwnStorySeenService>((_) => OwnStorySeenService());

/// Resolves whether *all* of the given own-story ids are locally seen.
/// Returns false while loading so the ring keeps its highlight until we
/// confirm — better to over-highlight briefly than to under-highlight
/// (the user would think their fresh story already "lost" its glow).
final ownStoriesAllSeenProvider =
    FutureProvider.family<bool, List<String>>((ref, storyIds) async {
  if (storyIds.isEmpty) return true;
  final svc = ref.watch(ownStorySeenServiceProvider);
  for (final id in storyIds) {
    if (!await svc.isSeen(id)) return false;
  }
  return true;
});
