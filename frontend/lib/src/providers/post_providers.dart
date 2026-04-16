import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/model/post_model.dart';
import '../services/post_service.dart';
import 'auth_providers.dart';

final postServiceProvider = Provider<PostService>((_) => PostService());

final feedProvider = StreamProvider<List<Post>>(
  (ref) => ref.watch(postServiceProvider).streamFeed(),
);

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
