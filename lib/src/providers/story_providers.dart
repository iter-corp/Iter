import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/story_service.dart';

final storyServiceProvider = Provider<StoryService>((_) => StoryService());

final activeStoriesProvider = StreamProvider<List<Story>>(
  (ref) => ref.watch(storyServiceProvider).streamActiveStories(),
);

/// Story ids the current app session has just viewed.
///
/// Viewing a story writes to `stories/{storyId}/viewers/{uid}`, but the
/// story rail listens to the parent story docs. This local mirror lets the
/// ring update immediately instead of waiting for a full page rebuild.
final locallyViewedStoryIdsProvider = StateProvider<Set<String>>(
  (_) => const <String>{},
);

/// Live viewers count for a single story doc. Cheap (one Firestore
/// snapshot subscription per story), read by the home story rail so
/// the author's ring can re-highlight when new viewers show up.
final storyViewersCountProvider =
    StreamProvider.family<int, String>(
  (ref, storyId) =>
      ref.watch(storyServiceProvider).streamViewersCount(storyId),
);
