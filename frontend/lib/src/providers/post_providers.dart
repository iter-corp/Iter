import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../features/model/post_model.dart';
import '../services/post_service.dart';
import 'auth_providers.dart';
import 'block_providers.dart';
import 'follow_providers.dart';

class TravelFeedQuery {
  final String placeQuery;
  final double? lat;
  final double? lng;
  final int limit;

  const TravelFeedQuery({
    this.placeQuery = '',
    this.lat,
    this.lng,
    this.limit = 60,
  });

  @override
  bool operator ==(Object other) {
    return other is TravelFeedQuery &&
        other.placeQuery == placeQuery &&
        other.lat == lat &&
        other.lng == lng &&
        other.limit == limit;
  }

  @override
  int get hashCode => Object.hash(placeQuery, lat, lng, limit);
}

final postServiceProvider = Provider<PostService>((_) => PostService());

final feedProvider = StreamProvider<List<Post>>((ref) {
  final currentUid = ref.watch(authStateProvider).value?.uid;
  if (currentUid == null) return const Stream.empty();

  final followService = ref.watch(followServiceProvider);
  final blockedStream = ref.watch(blockServiceProvider).getBlockedUsers(currentUid);

  return Rx.combineLatest3(
    ref.watch(postServiceProvider).streamFeed().onErrorReturn(<Post>[]),
    followService.getFollowing(currentUid).onErrorReturn(<String>[]),
    blockedStream.onErrorReturn(<String>[]),
    (List<Post> posts, List<String> following, List<String> blocked) {
      final allowed = {...following, currentUid};
      final blockedSet = blocked.toSet();
      return posts
          .where((p) => !blockedSet.contains(p.authorUid))
          .where((p) => !p.isPrivate || allowed.contains(p.authorUid))
          .toList();
    },
  );
});

final userPostsProvider = StreamProvider.family<List<Post>, String>(
  (ref, uid) => ref.watch(postServiceProvider).streamUserPosts(uid),
);

final travelFeedProvider =
    FutureProvider.family<List<Post>, TravelFeedQuery>((ref, query) async {
  return ref.watch(postServiceProvider).getTravelPosts(
        placeQuery: query.placeQuery,
        currentLat: query.lat,
        currentLng: query.lng,
        limit: query.limit,
      );
});

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
