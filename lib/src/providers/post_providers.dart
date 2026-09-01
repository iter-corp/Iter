import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

import '../features/model/post_model.dart';
import '../services/post_service.dart';
import 'auth_providers.dart';
import 'block_providers.dart';
import 'follow_providers.dart';

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

final qaFeedProvider = StreamProvider<List<Post>>((ref) {
  final currentUid = ref.watch(
    authStateProvider.select((a) => a.value?.uid),
  );
  if (currentUid == null) return const Stream.empty();

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
          .toList();
    },
  );
});

/// One item in the merged home feed — either a regular post or a
/// standalone Discuss question, tagged so the UI knows which card to
/// render for it.
class HomeFeedItem {
  final Post post;
  final bool isQa;
  const HomeFeedItem({required this.post, required this.isQa});
}

/// The home feed: regular posts and standalone Discuss questions (ones not
/// tied to any specific post — see [postDiscussionsProvider] for those)
/// merged into a single list, newest first. Replaces the old separate
/// Feed/Discuss tabs.
final homeFeedProvider = Provider<AsyncValue<List<HomeFeedItem>>>((ref) {
  final feed = ref.watch(feedProvider);
  final qa = ref.watch(qaFeedProvider);
  return feed.when(
    data: (feedPosts) => qa.when(
      data: (qaPosts) {
        final items = <HomeFeedItem>[
          ...feedPosts.map((p) => HomeFeedItem(post: p, isQa: false)),
          ...qaPosts
              .where((p) => p.sourcePostId == null || p.sourcePostId!.isEmpty)
              .map((p) => HomeFeedItem(post: p, isQa: true)),
        ]..sort((a, b) {
            final at = a.post.createdAt ?? DateTime(0);
            final bt = b.post.createdAt ?? DateTime(0);
            return bt.compareTo(at);
          });
        return AsyncValue.data(items);
      },
      loading: () => const AsyncValue.loading(),
      error: (e, st) => AsyncValue.error(e, st),
    ),
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

/// Discuss threads made about one specific post (its `sourcePostId`) —
/// shown on that post's own "swipe to see Discuss" panel. Reuses
/// [qaFeedProvider]'s already-open stream rather than opening a new one
/// per post card.
final postDiscussionsProvider =
    Provider.family<AsyncValue<List<Post>>, String>((ref, postId) {
  final qa = ref.watch(qaFeedProvider);
  return qa.whenData(
    (posts) => posts.where((p) => p.sourcePostId == postId).toList(),
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
