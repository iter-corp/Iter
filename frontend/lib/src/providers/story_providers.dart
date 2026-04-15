import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/story_service.dart';

final storyServiceProvider = Provider<StoryService>((_) => StoryService());

final activeStoriesProvider = StreamProvider<List<Story>>(
  (ref) => ref.watch(storyServiceProvider).streamActiveStories(),
);
