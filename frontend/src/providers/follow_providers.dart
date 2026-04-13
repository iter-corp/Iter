import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/follow_service.dart';
import 'auth_providers.dart';

final followServiceProvider = Provider<FollowService>((_) => FollowService());

final isFollowingProvider =
    StreamProvider.family<bool, String>((ref, targetUid) {
  final currentUser = ref.watch(authStateProvider).value;
  if (currentUser == null) return Stream.value(false);

  return ref.watch(followServiceProvider).isFollowing(
        currentUid: currentUser.uid,
        targetUid: targetUid,
      );
});

final followersProvider =
    StreamProvider.family<List<String>, String>((ref, uid) {
  return ref.watch(followServiceProvider).getFollowers(uid);
});

final followingProvider =
    StreamProvider.family<List<String>, String>((ref, uid) {
  return ref.watch(followServiceProvider).getFollowing(uid);
});
