import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/profile_visitor_service.dart';
import 'auth_providers.dart';

final profileVisitorServiceProvider =
    Provider<ProfileVisitorService>((_) => ProfileVisitorService());

/// Live list of users who visited the signed-in user's profile,
/// newest first.
final myProfileVisitorsProvider =
    StreamProvider<List<ProfileVisitorEntry>>((ref) {
  final me = ref.watch(authStateProvider).value?.uid;
  if (me == null) return Stream.value(const []);
  return ref.watch(profileVisitorServiceProvider).streamVisitors(me);
});

/// Live count of distinct profile visitors. Surfaced in settings as a
/// badge next to the "Profile visitors" entry.
final myProfileVisitorCountProvider = StreamProvider<int>((ref) {
  final me = ref.watch(authStateProvider).value?.uid;
  if (me == null) return Stream.value(0);
  return ref.watch(profileVisitorServiceProvider).streamVisitorCount(me);
});
