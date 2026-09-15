import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/follow_service.dart';
import 'auth_providers.dart';

final followServiceProvider = Provider<FollowService>((_) => FollowService());

final isFollowingProvider =
    StreamProvider.family<bool, String>((ref, targetUid) {
  final currentUid = ref.watch(authStateProvider.select((a) => a.value?.uid));
  if (currentUid == null) return Stream.value(false);

  return ref.watch(followServiceProvider).isFollowing(
        currentUid: currentUid,
        targetUid: targetUid,
      );
});

final followersProvider =
    StreamProvider.family<List<String>, String>((ref, uid) {
  final sessionUid = ref.watch(authStateProvider.select((a) => a.value?.uid));
  if (sessionUid == null) return Stream.value(const []);

  return ref.watch(followServiceProvider).getFollowers(uid);
});

final followingProvider =
    StreamProvider.family<List<String>, String>((ref, uid) {
  final sessionUid = ref.watch(authStateProvider.select((a) => a.value?.uid));
  if (sessionUid == null) return Stream.value(const []);

  return ref.watch(followServiceProvider).getFollowing(uid);
});

final hasRequestedFollowProvider =
    StreamProvider.family<bool, String>((ref, targetUid) {
  final currentUid = ref.watch(authStateProvider.select((a) => a.value?.uid));
  if (currentUid == null) return Stream.value(false);

  return ref.watch(followServiceProvider).hasRequestedFollow(
        currentUid: currentUid,
        targetUid: targetUid,
      );
});

final followRequestsProvider =
    StreamProvider.family<List<String>, String>((ref, uid) {
  final sessionUid = ref.watch(authStateProvider.select((a) => a.value?.uid));
  if (sessionUid == null) return Stream.value(const []);

  return ref.watch(followServiceProvider).getFollowRequests(uid);
});

// pendingFollowsCompleterProvider removed as acceptance is now atomic.
