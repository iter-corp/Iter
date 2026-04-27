import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/block_service.dart';
import 'auth_providers.dart';

final blockServiceProvider = Provider<BlockService>((_) => BlockService());

/// Whether the current user has blocked [targetUid].
final isBlockedProvider =
    StreamProvider.family<bool, String>((ref, targetUid) {
  final currentUser = ref.watch(authStateProvider).value ??
      ref.watch(authServiceProvider).currentUser;
  if (currentUser == null) return Stream.value(false);

  return ref.watch(blockServiceProvider).isBlocked(
        currentUid: currentUser.uid,
        targetUid: targetUid,
      );
});

/// Whether [targetUid] has blocked the current user.
final isBlockedByProvider =
    StreamProvider.family<bool, String>((ref, targetUid) {
  final currentUser = ref.watch(authStateProvider).value ??
      ref.watch(authServiceProvider).currentUser;
  if (currentUser == null) return Stream.value(false);

  return ref.watch(blockServiceProvider).isBlockedBy(
        currentUid: currentUser.uid,
        targetUid: targetUid,
      );
});

/// List of UIDs that the current user has blocked.
final blockedUsersProvider = StreamProvider<List<String>>((ref) {
  final currentUser = ref.watch(authStateProvider).value ??
      ref.watch(authServiceProvider).currentUser;
  if (currentUser == null) return Stream.value(const []);

  return ref.watch(blockServiceProvider).getBlockedUsers(currentUser.uid);
});
