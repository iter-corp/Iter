import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/model/post_model.dart';
import '../services/follow_service.dart';
import '../services/post_service.dart';
import 'auth_providers.dart';
import 'follow_providers.dart';

final postServiceProvider = Provider<PostService>((_) => PostService());

final feedProvider = StreamProvider<List<Post>>((ref) {
  final currentUid = ref.watch(authStateProvider).value?.uid;
  if (currentUid == null) return const Stream.empty();

  final followService = ref.watch(followServiceProvider);

  // Combine raw posts with the current user's following list so that
  // followers-only posts are hidden from users who don't follow the author.
  return ref.watch(postServiceProvider).streamFeed().asyncExpand((posts) {
    return followService.getFollowing(currentUid).map((following) {
      final allowed = {...following, currentUid};
      return posts
          .where((p) => !p.isPrivate || allowed.contains(p.authorUid))
          .toList();
    });
  });
});

final userPostsProvider = StreamProvider.family<List<Post>, String>(
  (ref, uid) => ref.watch(postServiceProvider).streamUserPosts(uid),
);

final isLikedProvider = StreamProvider.family<bool, String>((ref, postId) {
  // Watch auth so the stream rebuilds after logout/re-login, preventing a
  // stuck Stream.value(false) created while auth was initialising.
  final uid = (ref.watch(authStateProvider).value ??
          ref.watch(authServiceProvider).currentUser)
      ?.uid;
  if (uid == null) return Stream.value(false);
  return ref.watch(postServiceProvider).streamIsLiked(postId, uid: uid);
});

final isRepostedProvider = StreamProvider.family<bool, String>((ref, postId) {
  final uid = (ref.watch(authStateProvider).value ??
          ref.watch(authServiceProvider).currentUser)
      ?.uid;
  if (uid == null) return Stream.value(false);
  return ref.watch(postServiceProvider).streamIsReposted(postId, uid: uid);
});

final userRepostsProvider = StreamProvider.family<List<Post>, String>(
  (ref, uid) => ref.watch(postServiceProvider).streamUserReposts(uid),
);

final isSavedProvider = StreamProvider.family<bool, String>((ref, postId) {
  final uid = (ref.watch(authStateProvider).value ??
          ref.watch(authServiceProvider).currentUser)
      ?.uid;
  if (uid == null) return Stream.value(false);
  return ref.watch(postServiceProvider).streamIsSaved(postId, uid: uid);
});

final userSavedProvider = StreamProvider.family<List<Post>, String>(
  (ref, uid) => ref.watch(postServiceProvider).streamUserSaved(uid),
);
