import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/live_service.dart';

final liveServiceProvider = Provider<LiveService>((_) => LiveService());

final activeStreamsProvider = StreamProvider<List<LiveStream>>((ref) {
  return ref.watch(liveServiceProvider).getActiveStreams();
});
