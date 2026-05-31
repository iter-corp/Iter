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

/// Fetches a single post by id. Used to embed a post inside other
/// screens (e.g. the discussed post shown in a Discuss thread).
final singlePostProvider =
    FutureProvider.family<Post?, String>((ref, postId) async {
  return ref.watch(postServiceProvider).getPostById(postId);
});

final feedProvider = StreamProvider<List<Post>>((ref) {
  // Rebuild only when the effective UID changes to avoid restarting the feed
  // stream during transient auth state re-emissions.
  final currentUid = ref.watch(
    authStateProvider.select((a) => a.value?.uid),
  );
  if (currentUid == null) return const Stream.empty();

  final followService = ref.watch(followServiceProvider);
  final blockedStream =
      ref.watch(blockServiceProvider).getBlockedUsers(currentUid);

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

/// When non-null, the Discuss tab is filtered to only show discussions whose
/// `sourcePostId` matches this id — i.e. all the discussions made about one
/// specific post. Set by "view in discuss" on a post; cleared (back to the
/// full discuss feed) by the X on the filter header. Null = show everything.
final discussFilterPostIdProvider = StateProvider<String?>((_) => null);

final qaFeedProvider = StreamProvider<List<Post>>((ref) {
  final currentUid = ref.watch(
    authStateProvider.select((a) => a.value?.uid),
  );
  if (currentUid == null) return const Stream.empty();

  final filterPostId = ref.watch(discussFilterPostIdProvider);
  final followService = ref.watch(followServiceProvider);
  final blockedStream =
      ref.watch(blockServiceProvider).getBlockedUsers(currentUid);

  return Rx.combineLatest3(
    ref.watch(postServiceProvider).streamQaFeed().onErrorReturn(<Post>[]),
    followService.getFollowing(currentUid).onErrorReturn(<String>[]),
    blockedStream.onErrorReturn(<String>[]),
    (List<Post> posts, List<String> following, List<String> blocked) {
      final allowed = {...following, currentUid};
      final blockedSet = blocked.toSet();
      return posts
          .where((p) => !blockedSet.contains(p.authorUid))
          .where((p) => !p.isPrivate || allowed.contains(p.authorUid))
          // When a post filter is active, keep only discussions about it.
          .where((p) => filterPostId == null || p.sourcePostId == filterPostId)
          .toList();
    },
  );
});

final userPostsProvider = StreamProvider.family<List<Post>, String>((ref, uid) {
  // Gate on auth being settled. posts require signedIn() in Firestore rules;
  // opening the stream before the token propagates causes permission-denied.
  final authed = ref.watch(authStateProvider.select((a) => a.value?.uid));
  if (authed == null) return const Stream.empty();
  return ref.watch(postServiceProvider).streamUserPosts(uid);
});

final userQaAskedProvider =
    StreamProvider.family<List<Post>, String>((ref, uid) {
  final authed = ref.watch(authStateProvider.select((a) => a.value?.uid));
  if (authed == null) return const Stream.empty();
  return ref.watch(postServiceProvider).streamUserQaAsked(uid);
});

final userQaAnsweredProvider =
    StreamProvider.family<List<Post>, String>((ref, uid) {
  final authed = ref.watch(authStateProvider.select((a) => a.value?.uid));
  if (authed == null) return const Stream.empty();
  return ref.watch(postServiceProvider).streamUserQaAnswered(uid);
});

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
  final uid = ref.watch(authStateProvider.select((a) => a.value?.uid));
  if (uid == null) return Stream.value(false);
  return ref.watch(postServiceProvider).streamIsLiked(postId, uid: uid);
});

final isRepostedProvider = StreamProvider.family<bool, String>((ref, postId) {
  final uid = ref.watch(authStateProvider.select((a) => a.value?.uid));
  if (uid == null) return Stream.value(false);
  return ref.watch(postServiceProvider).streamIsReposted(postId, uid: uid);
});

/// Live count of reposts for a post — drives the small number rendered
/// next to the repost icon, the same way `${post.likesCount}` appears
/// next to the heart.
final repostsCountProvider = StreamProvider.family<int, String>((ref, postId) {
  return ref.watch(postServiceProvider).streamRepostsCount(postId);
});

final repostUserIdsProvider =
    StreamProvider.family<List<String>, String>((ref, postId) {
  return ref.watch(postServiceProvider).streamRepostUserIds(postId);
});

final userRepostsProvider =
    StreamProvider.family<List<Post>, String>((ref, uid) {
  final authed = ref.watch(authStateProvider.select((a) => a.value?.uid));
  if (authed == null) return const Stream.empty();
  return ref.watch(postServiceProvider).streamUserReposts(uid);
});

final isSavedProvider = StreamProvider.family<bool, String>((ref, postId) {
  final uid = ref.watch(authStateProvider.select((a) => a.value?.uid));
  if (uid == null) return Stream.value(false);
  return ref.watch(postServiceProvider).streamIsSaved(postId, uid: uid);
});

final userSavedProvider = StreamProvider.family<List<Post>, String>((ref, uid) {
  final authed = ref.watch(authStateProvider.select((a) => a.value?.uid));
  if (authed == null) return const Stream.empty();
  return ref.watch(postServiceProvider).streamUserSaved(uid);
});
